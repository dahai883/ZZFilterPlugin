#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSMutableDictionary<NSString *, NSValue *> *ZZOriginalForwardIMPs;
static NSMutableSet<NSString *> *ZZHookedSelectors;
static NSUInteger ZZRuntimeCalls;
static NSUInteger ZZRuntimeScannedClasses;
static NSUInteger ZZRuntimeMatchedClasses;
static NSUInteger ZZRuntimeMatchedMethods;
static NSUInteger ZZRuntimeHookFailures;
static NSUInteger ZZRuntimeLastClassCount;
static NSUInteger ZZRuntimeLastMethodCount;
static NSString *ZZRuntimeLastSummary;

static BOOL ZZLooksLikeModelArray(id obj) {
    if (![obj isKindOfClass:NSArray.class]) return NO;
    NSArray *a = obj;
    if (!a.count) return YES;
    NSUInteger inspected = MIN((NSUInteger)8, a.count);
    NSUInteger modelish = 0;
    for (NSUInteger i = 0; i < inspected; i++) {
        id item = a[i];
        if ([item isKindOfClass:NSDictionary.class] ||
            [item respondsToSelector:@selector(dictionaryWithValuesForKeys:)]) modelish++;
    }
    return modelish > 0;
}

static void ZZFilterInvocationArguments(NSInvocation *invocation) {
    ZZRuntimeCalls += 1;
    if (!ZZSettings.shared.enabled) return;

    NSUInteger count = invocation.methodSignature.numberOfArguments;
    for (NSUInteger i = 2; i < count; i++) {
        const char *argType = [invocation.methodSignature getArgumentTypeAtIndex:i];
        if (!argType || argType[0] != '@') continue;
        __unsafe_unretained id value = nil;
        [invocation getArgument:&value atIndex:i];
        if (!ZZLooksLikeModelArray(value)) continue;

        NSArray *filtered = ZZFilteredModels((NSArray *)value);
        if (filtered != value) {
            id replacement = filtered;
            [invocation setArgument:&replacement atIndex:i];
            NSLog(@"[ZZFilterUI] runtime selector=%@ array=%lu -> %lu",
                  NSStringFromSelector(invocation.selector),
                  (unsigned long)[(NSArray *)value count],
                  (unsigned long)filtered.count);
        }
        break;
    }
}

static void ZZForwardInvocation(id self, SEL _cmd, NSInvocation *invocation) {
    Class cls = object_getClass(self);
    NSString *key = [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(invocation.selector)];
    NSValue *impValue = ZZOriginalForwardIMPs[key];
    if (impValue) {
        ZZFilterInvocationArguments(invocation);
        SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", NSStringFromSelector(invocation.selector)]);
        if ([self respondsToSelector:alias]) {
            invocation.selector = alias;
            [invocation invokeWithTarget:self];
            return;
        }
    }

    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    IMP originalFwd = (IMP)[ZZOriginalForwardIMPs[fwdKey] pointerValue];
    if (originalFwd && originalFwd != (IMP)ZZForwardInvocation) {
        ((void (*)(id, SEL, NSInvocation *))originalFwd)(self, _cmd, invocation);
        return;
    }
    [self doesNotRecognizeSelector:invocation.selector];
}

static BOOL ZZHookSelector(Class cls, SEL selector) {
    if (!cls || !selector) return NO;

    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    // If the selector is inherited, create a class-local copy first. This
    // avoids modifying a shared superclass implementation for every subclass.
    Method direct = class_getInstanceMethod(cls, selector);
    BOOL isDirect = NO;
    unsigned int directCount = 0;
    Method *directMethods = class_copyMethodList(cls, &directCount);
    if (directMethods) {
        for (unsigned int i = 0; i < directCount; i++) {
            if (method_getName(directMethods[i]) == selector) { isDirect = YES; break; }
        }
        free(directMethods);
    }
    if (!isDirect) {
        IMP inheritedIMP = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        if (!class_addMethod(cls, selector, inheritedIMP, types)) {
            ZZRuntimeHookFailures += 1;
            return NO;
        }
        direct = class_getInstanceMethod(cls, selector);
        if (!direct) {
            ZZRuntimeHookFailures += 1;
            return NO;
        }
        method = direct;
    }

    NSString *hookKey = [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(selector)];
    if ([ZZHookedSelectors containsObject:hookKey]) return YES;

    SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", NSStringFromSelector(selector)]);
    if (!class_getInstanceMethod(cls, alias)) {
        class_addMethod(cls, alias, method_getImplementation(method), method_getTypeEncoding(method));
    }

    Method fwd = class_getInstanceMethod(cls, @selector(forwardInvocation:));
    IMP originalFwd = fwd ? method_getImplementation(fwd) : NULL;
    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    if (![ZZOriginalForwardIMPs objectForKey:fwdKey]) {
        if (originalFwd) ZZOriginalForwardIMPs[fwdKey] = [NSValue valueWithPointer:originalFwd];
        class_replaceMethod(cls, @selector(forwardInvocation:), (IMP)ZZForwardInvocation, "v@:@");
    }

    ZZOriginalForwardIMPs[hookKey] = [NSValue valueWithPointer:method_getImplementation(method)];
    IMP forwardingIMP = (IMP)dlsym(RTLD_DEFAULT, "objc_msgForward");
    if (!forwardingIMP) {
        ZZRuntimeHookFailures += 1;
        [ZZOriginalForwardIMPs removeObjectForKey:hookKey];
        NSLog(@"[ZZFilterUI] cannot resolve objc_msgForward; skip %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(selector));
        return NO;
    }

    [ZZHookedSelectors addObject:hookKey];
    method_setImplementation(method, forwardingIMP);
    NSLog(@"[ZZFilterUI] hooked %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
    return YES;
}

NSUInteger ZZRuntimeFilteringHookCount(void) { return ZZHookedSelectors.count; }
NSUInteger ZZRuntimeFilteringCalls(void) { return ZZRuntimeCalls; }
NSUInteger ZZRuntimeFilteringScannedClasses(void) { return ZZRuntimeScannedClasses; }
NSUInteger ZZRuntimeFilteringMatchedClasses(void) { return ZZRuntimeMatchedClasses; }
NSUInteger ZZRuntimeFilteringMatchedMethods(void) { return ZZRuntimeMatchedMethods; }
NSUInteger ZZRuntimeFilteringHookFailures(void) { return ZZRuntimeHookFailures; }
NSString *ZZRuntimeFilteringLastSummary(void) { return ZZRuntimeLastSummary ?: @"尚未扫描"; }

void ZZInstallRuntimeFiltering(void) {
    static dispatch_once_t initOnce;
    dispatch_once(&initOnce, ^{
        ZZOriginalForwardIMPs = [NSMutableDictionary dictionary];
        ZZHookedSelectors = [NSMutableSet set];
    });

    NSArray<NSString *> *selectors = @[
        @"addCellWithModel:forSection:className:",
        @"addCellWithModel:forSection:className:tag:",
        @"addCellsWithModelArray:forSection:className:",
        @"addCellsWithModelArray:forSection:className:tag:",
        @"insertCellsWithModelArray:forSection:className:pos:",
        @"insertCellsWithModelArray:forSection:className:tag:pos:",
        @"p_addCellsWithModelArray:forSection:className:tag:",
        @"p_insertCellsWithModelArray:forSection:className:tag:pos:",
        @"addListingGoodsWithRespModel:",
        @"reloadListingGoodsWithRespModel:",
        @"requestDataWithPageIndex:"
    ];

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        ZZRuntimeLastSummary = @"运行时类列表为空";
        NSLog(@"[ZZFilterUI] runtime discovery: no classes yet");
        return;
    }

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    int actual = objc_getClassList(classes, classCount);
    NSUInteger matchedClasses = 0;
    NSUInteger matchedMethods = 0;
    NSUInteger newlyHooked = 0;
    NSUInteger methodCountTotal = 0;

    for (int i = 0; i < actual; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        if (methods) {
            methodCountTotal += count;
            free(methods);
        }

        BOOL classMatched = NO;
        for (NSString *selectorName in selectors) {
            SEL sel = NSSelectorFromString(selectorName);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) continue;
            classMatched = YES;
            matchedMethods += 1;
            NSUInteger before = ZZHookedSelectors.count;
            if (ZZHookSelector(cls, sel) && ZZHookedSelectors.count > before) newlyHooked += 1;
        }
        if (classMatched) matchedClasses += 1;
    }
    free(classes);

    ZZRuntimeScannedClasses = (NSUInteger)actual;
    ZZRuntimeMatchedClasses = matchedClasses;
    ZZRuntimeMatchedMethods = matchedMethods;
    ZZRuntimeLastClassCount = (NSUInteger)actual;
    ZZRuntimeLastMethodCount = methodCountTotal;
    ZZRuntimeLastSummary = [NSString stringWithFormat:@"类=%lu 方法=%lu 匹配类=%lu 匹配方法=%lu 新Hook=%lu 失败=%lu 总Hook=%lu",
                            (unsigned long)ZZRuntimeLastClassCount,
                            (unsigned long)ZZRuntimeLastMethodCount,
                            (unsigned long)matchedClasses,
                            (unsigned long)matchedMethods,
                            (unsigned long)newlyHooked,
                            (unsigned long)ZZRuntimeHookFailures,
                            (unsigned long)ZZHookedSelectors.count];
    NSLog(@"[ZZFilterUI] runtime discovery: %@", ZZRuntimeLastSummary);
}
