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

static void ZZHookSelector(Class cls, SEL selector) {
    if (!cls || !selector) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    NSString *hookKey = [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(selector)];
    if ([ZZHookedSelectors containsObject:hookKey]) return;

    SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", NSStringFromSelector(selector)]);
    if (!class_getInstanceMethod(cls, alias)) {
        class_addMethod(cls, alias, method_getImplementation(method), method_getTypeEncoding(method));
    }

    // Install forwardInvocation only once per target class, preserving the
    // existing implementation for selectors we do not own.
    Method fwd = class_getInstanceMethod(cls, @selector(forwardInvocation:));
    IMP originalFwd = fwd ? method_getImplementation(fwd) : NULL;
    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    if (![ZZOriginalForwardIMPs objectForKey:fwdKey]) {
        if (originalFwd) ZZOriginalForwardIMPs[fwdKey] = [NSValue valueWithPointer:originalFwd];
        class_replaceMethod(cls, @selector(forwardInvocation:), (IMP)ZZForwardInvocation, "v@:@");
    }

    ZZOriginalForwardIMPs[hookKey] = [NSValue valueWithPointer:method_getImplementation(method)];
    [ZZHookedSelectors addObject:hookKey];

    // Avoid a direct link against objc_msgForward. Some iOS SDK/linker
    // combinations do not expose that symbol to dylib linkers even though
    // the runtime can resolve it. Resolve it dynamically instead.
    IMP forwardingIMP = (IMP)dlsym(RTLD_DEFAULT, "objc_msgForward");
    if (!forwardingIMP) {
        NSLog(@"[ZZFilterUI] cannot resolve objc_msgForward; skip %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(selector));
        [ZZHookedSelectors removeObject:hookKey];
        [ZZOriginalForwardIMPs removeObjectForKey:hookKey];
        return;
    }
    method_setImplementation(method, forwardingIMP);
    NSLog(@"[ZZFilterUI] hooked %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector));
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

    // The reference build exposes these list-rendering selectors.  Instead of
    // assuming a particular controller class name, discover classes that
    // actually implement the selectors in the running, authorized host.
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
        NSLog(@"[ZZFilterUI] runtime discovery: no classes yet");
        return;
    }

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    int actual = objc_getClassList(classes, classCount);
    NSUInteger discovered = 0;
    NSUInteger newlyHooked = 0;

    for (int i = 0; i < actual; i++) {
        Class cls = classes[i];
        if (!cls) continue;

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;

        for (unsigned int m = 0; m < methodCount; m++) {
            SEL implemented = method_getName(methods[m]);
            NSString *name = NSStringFromSelector(implemented);
            if (![selectors containsObject:name]) continue;
            discovered++;

            NSUInteger before = ZZHookedSelectors.count;
            ZZHookSelector(cls, implemented);
            if (ZZHookedSelectors.count > before) newlyHooked++;
        }
        free(methods);
    }
    free(classes);

    NSLog(@"[ZZFilterUI] runtime discovery: classes=%d methods=%lu newlyHooked=%lu totalHooked=%lu",
          actual, (unsigned long)discovered, (unsigned long)newlyHooked,
          (unsigned long)ZZHookedSelectors.count);
}
