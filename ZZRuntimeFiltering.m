#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSMutableDictionary<NSString *, NSValue *> *ZZOriginalForwardIMPs;
static NSMutableSet<NSString *> *ZZHookedSelectors;
static NSUInteger ZZRuntimeCalls;

static BOOL ZZLooksLikeModelArray(id obj) {
    if (![obj isKindOfClass:NSArray.class]) return NO;
    NSArray *a = obj;
    if (!a.count) return YES;
    NSUInteger inspected = MIN((NSUInteger)6, a.count);
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
    const char *types = invocation.methodSignature.methodReturnType;
    (void)types;

    NSUInteger count = invocation.methodSignature.numberOfArguments;
    for (NSUInteger i = 2; i < count; i++) {
        const char *argType = [invocation.methodSignature getArgumentTypeAtIndex:i];
        if (!argType || argType[0] != '@') continue;
        __unsafe_unretained id value = nil;
        [invocation getArgument:&value atIndex:i];
        if (ZZLooksLikeModelArray(value)) {
            NSArray *filtered = ZZFilteredModels(value);
            if (filtered != value) {
                id replacement = filtered;
                [invocation setArgument:&replacement atIndex:i];
                NSLog(@"[ZZFilterUI] runtime selector=%@ array=%lu -> %lu",
                      NSStringFromSelector(invocation.selector),
                      (unsigned long)[value count], (unsigned long)[filtered count]);
            }
            break;
        }
    }
}

static void ZZForwardInvocation(id self, SEL _cmd, NSInvocation *invocation) {
    NSString *key = [NSString stringWithFormat:@"%p:%@", object_getClass(self), NSStringFromSelector(invocation.selector)];
    NSValue *impValue = ZZOriginalForwardIMPs[key];
    if (impValue) {
        ZZFilterInvocationArguments(invocation);
        SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", NSStringFromSelector(invocation.selector)]);
        invocation.selector = alias;
        [invocation invokeWithTarget:self];
        return;
    }

    // Fall back to the class's original forwarding implementation.
    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", object_getClass(self)];
    NSValue *fwdValue = ZZOriginalForwardIMPs[fwdKey];
    IMP originalFwd = (IMP)[fwdValue pointerValue];
    if (originalFwd && originalFwd != (IMP)ZZForwardInvocation) {
        ((void (*)(id, SEL, NSInvocation *))originalFwd)(self, _cmd, invocation);
        return;
    }
    [self doesNotRecognizeSelector:invocation.selector];
}

static BOOL ZZClassDeclaresSelector(Class cls, SEL selector, Method *outMethod) {
    if (!cls || !selector) return NO;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { found = methods[i]; break; }
    }
    if (methods) free(methods);
    if (outMethod) *outMethod = found;
    return found != NULL;
}

static BOOL ZZHookSelector(Class cls, SEL selector) {
    if (!cls || !selector) return NO;

    // V7 could destabilize the host by turning inherited methods into
    // class-local methods and then replacing forwarding on many classes.
    // V8 only touches methods that the class itself declares.
    Method method = NULL;
    if (!ZZClassDeclaresSelector(cls, selector, &method) || !method) return NO;

    const char *types = method_getTypeEncoding(method);
    if (!types || types[0] != 'v') {
        NSLog(@"[ZZFilterUI] skip non-void %@ %@ types=%s",
              NSStringFromClass(cls), NSStringFromSelector(selector), types ?: "?");
        return NO;
    }

    NSString *hookKey = [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(selector)];
    if ([ZZHookedSelectors containsObject:hookKey]) return YES;

    IMP original = method_getImplementation(method);
    SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", NSStringFromSelector(selector)]);
    if (!class_getInstanceMethod(cls, alias)) {
        if (!class_addMethod(cls, alias, original, types)) {
            NSLog(@"[ZZFilterUI] alias add failed %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
            return NO;
        }
    }

    IMP forwardingIMP = (IMP)dlsym(RTLD_DEFAULT, "objc_msgForward");
    if (!forwardingIMP) {
        NSLog(@"[ZZFilterUI] cannot resolve objc_msgForward; skip %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(selector));
        return NO;
    }

    // Preserve a class-local forwardInvocation implementation only if it is
    // already declared by the class. Otherwise install ours and keep the
    // original inherited implementation out of the hook path.
    Method fwd = NULL;
    BOOL hasDirectForward = ZZClassDeclaresSelector(cls, @selector(forwardInvocation:), &fwd);
    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    if (![ZZOriginalForwardIMPs objectForKey:fwdKey]) {
        if (hasDirectForward && fwd) {
            ZZOriginalForwardIMPs[fwdKey] = [NSValue valueWithPointer:method_getImplementation(fwd)];
        } else {
            ZZOriginalForwardIMPs[fwdKey] = [NSValue valueWithPointer:NULL];
        }
        class_replaceMethod(cls, @selector(forwardInvocation:), (IMP)ZZForwardInvocation, "v@:@");
    }

    ZZOriginalForwardIMPs[hookKey] = [NSValue valueWithPointer:original];
    method_setImplementation(method, forwardingIMP);
    [ZZHookedSelectors addObject:hookKey];
    NSLog(@"[ZZFilterUI] hooked-direct %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
    return YES;
}

NSUInteger ZZRuntimeFilteringHookCount(void) {
    return ZZHookedSelectors.count;
}

NSUInteger ZZRuntimeFilteringCalls(void) {
    return ZZRuntimeCalls;
}

void ZZInstallRuntimeFiltering(void) {
    static dispatch_once_t initOnce;
    dispatch_once(&initOnce, ^{
        ZZOriginalForwardIMPs = [NSMutableDictionary dictionary];
        ZZHookedSelectors = [NSMutableSet set];
    });

    NSArray<NSString *> *selectors = @[
        @"addCellsWithModelArray:forSection:className:",
        @"addCellsWithModelArray:forSection:className:tag:",
        @"insertCellsWithModelArray:forSection:className:pos:",
        @"insertCellsWithModelArray:forSection:className:tag:pos:",
        @"p_addCellsWithModelArray:forSection:className:tag:",
        @"p_insertCellsWithModelArray:forSection:className:tag:pos:",
        @"addListingGoodsWithRespModel:",
        @"reloadListingGoodsWithRespModel:"
    ];

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        ZZRuntimeScannedClasses = 0;
        ZZRuntimeMatchedClasses = 0;
        ZZRuntimeMatchedMethods = 0;
        ZZRuntimeHookFailures = 0;
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
        methodCountTotal += count;
        BOOL classMatched = NO;
        if (methods) {
            for (unsigned int m = 0; m < count; m++) {
                SEL implemented = method_getName(methods[m]);
                NSString *name = NSStringFromSelector(implemented);
                if (![selectors containsObject:name]) continue;
                classMatched = YES;
                matchedMethods += 1;
                NSUInteger before = ZZHookedSelectors.count;
                if (ZZHookSelector(cls, implemented) && ZZHookedSelectors.count > before) newlyHooked += 1;
            }
            free(methods);
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

