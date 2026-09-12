#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

/*
 * Reference-informed, activation-free UI adapter.
 *
 * The supplied reference binary exposes the following public ObjC selector
 * names around listing rendering.  This implementation uses only those
 * selector names and never touches its activation/token/security routines.
 * It deliberately keeps the hook generic: it filters object-array arguments
 * when a host listing method receives them, while preserving the original
 * implementation through NSInvocation.
 */

static NSMutableDictionary<NSString *, NSValue *> *ZZOriginalIMPs;
static NSMutableSet<NSString *> *ZZHooked;
static NSMutableSet<NSString *> *ZZForwardInstalled;
static NSUInteger ZZCalls;

static BOOL ZZLooksLikeModelArray(id obj) {
    if (![obj isKindOfClass:NSArray.class]) return NO;
    NSArray *a = obj;
    if (a.count == 0) return YES;
    NSUInteger n = MIN((NSUInteger)8, a.count);
    NSUInteger modelish = 0;
    for (NSUInteger i = 0; i < n; i++) {
        id item = a[i];
        if ([item isKindOfClass:NSDictionary.class] ||
            [item respondsToSelector:@selector(dictionaryWithValuesForKeys:)]) {
            modelish++;
        }
    }
    return modelish > 0;
}

static void ZZFilterInvocationArguments(NSInvocation *inv) {
    ZZCalls++;
    if (!ZZSettings.shared.enabled) return;

    NSUInteger argc = inv.methodSignature.numberOfArguments;
    for (NSUInteger i = 2; i < argc; i++) {
        const char *t = [inv.methodSignature getArgumentTypeAtIndex:i];
        if (!t || t[0] != '@') continue;
        __unsafe_unretained id value = nil;
        [inv getArgument:&value atIndex:i];
        if (!ZZLooksLikeModelArray(value)) continue;

        NSArray *filtered = ZZFilteredModels(value);
        if (filtered.count != [value count]) {
            id replacement = filtered;
            [inv setArgument:&replacement atIndex:i];
            NSLog(@"[ZZFilterUI] filtered %@ %@ %lu->%lu",
                  NSStringFromClass(object_getClass(inv.target)),
                  NSStringFromSelector(inv.selector),
                  (unsigned long)[value count], (unsigned long)filtered.count);
        }
        // A listing render call normally has one model-array argument.
        break;
    }
}

static void ZZForwardInvocation(id self, SEL _cmd, NSInvocation *inv) {
    Class cls = object_getClass(self);
    NSString *selectorName = NSStringFromSelector(inv.selector);
    NSString *key = [NSString stringWithFormat:@"%p:%@", cls, selectorName];
    NSValue *orig = ZZOriginalIMPs[key];

    if (orig) {
        ZZFilterInvocationArguments(inv);
        SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", selectorName]);
        if ([self respondsToSelector:alias]) {
            inv.selector = alias;
            [inv invokeWithTarget:self];
            return;
        }
        IMP imp = (IMP)orig.pointerValue;
        if (imp) {
            // Preserve the original ABI/signature by invoking it through the
            // NSInvocation generated from the original method signature.
            // NSInvocation cannot call an arbitrary IMP directly, so create a
            // temporary selector with the saved implementation when possible.
            Method m = class_getInstanceMethod(cls, inv.selector);
            const char *types = m ? method_getTypeEncoding(m) : "v@:@";
            SEL fallback = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", selectorName]);
            if (!class_getInstanceMethod(cls, fallback)) {
                class_addMethod(cls, fallback, imp, types);
            }
            inv.selector = fallback;
            [inv invokeWithTarget:self];
            return;
        }
    }

    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    IMP original = (IMP)ZZOriginalIMPs[fwdKey].pointerValue;
    if (original && original != (IMP)ZZForwardInvocation) {
        ((void (*)(id, SEL, NSInvocation *))original)(self, _cmd, inv);
        return;
    }
    [self doesNotRecognizeSelector:inv.selector];
}

static void ZZHookClassSelector(Class cls, SEL selector) {
    if (!cls || !selector) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    NSString *name = NSStringFromSelector(selector);
    NSString *key = [NSString stringWithFormat:@"%p:%@", cls, name];
    if ([ZZHooked containsObject:key]) return;

    IMP originalIMP = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    SEL alias = NSSelectorFromString([NSString stringWithFormat:@"zz_orig_%@", name]);
    if (!class_getInstanceMethod(cls, alias)) {
        class_addMethod(cls, alias, originalIMP, types);
    }

    NSString *fwdKey = [NSString stringWithFormat:@"%p:forwardInvocation", cls];
    if (![ZZForwardInstalled containsObject:fwdKey]) {
        Method fwd = class_getInstanceMethod(cls, @selector(forwardInvocation:));
        IMP oldFwd = fwd ? method_getImplementation(fwd) : NULL;
        if (oldFwd) ZZOriginalIMPs[fwdKey] = [NSValue valueWithPointer:oldFwd];
        class_replaceMethod(cls, @selector(forwardInvocation:), (IMP)ZZForwardInvocation, "v@:@");
        [ZZForwardInstalled addObject:fwdKey];
    }

    ZZOriginalIMPs[key] = [NSValue valueWithPointer:originalIMP];
    [ZZHooked addObject:key];

    // objc_msgForward is declared by objc/message.h.  Resolve it at runtime
    // to remain compatible with restricted SDK link environments.
    void *sym = dlsym(RTLD_DEFAULT, "objc_msgForward");
    IMP forwardIMP = (IMP)sym;
    if (!forwardIMP) {
        NSLog(@"[ZZFilterUI] objc_msgForward unavailable for %@ %@", NSStringFromClass(cls), name);
        [ZZHooked removeObject:key];
        [ZZOriginalIMPs removeObjectForKey:key];
        return;
    }
    method_setImplementation(method, forwardIMP);
    NSLog(@"[ZZFilterUI] HOOK %@ %@ types=%s", NSStringFromClass(cls), name, types ?: "?");
}

NSUInteger ZZRuntimeFilteringHookCount(void) { return ZZHooked.count; }
NSUInteger ZZRuntimeFilteringCalls(void) { return ZZCalls; }

void ZZInstallRuntimeFiltering(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZZOriginalIMPs = [NSMutableDictionary dictionary];
        ZZHooked = [NSMutableSet set];
        ZZForwardInstalled = [NSMutableSet set];
    });

    /* Exact selector inventory observed in the supplied successful build. */
    static NSArray<NSString *> *names;
    static dispatch_once_t namesOnce;
    dispatch_once(&namesOnce, ^{
        names = @[
            @"addCellWithModel:forSection:className:",
            @"addCellWithModel:forSection:className:tag:",
            @"addCellsWithModelArray:forSection:className:",
            @"addCellsWithModelArray:forSection:className:tag:",
            @"insertCellsWithModelArray:forSection:className:pos:",
            @"insertCellsWithModelArray:forSection:className:tag:pos:",
            @"p_addCellsWithModelArray:forSection:className:tag:",
            @"p_insertCellsWithModelArray:forSection:className:tag:pos:",
            @"reloadListingGoodsWithRespModel:",
            @"addListingGoodsWithRespModel:",
            @"requestDataWithPageIndex:",
            @"setPageIndex:"
        ];
    });

    // Use objc_copyClassList rather than the two-call objc_getClassList pattern.
    // Some injected/runtime environments can report zero from the size-query
    // form even though classes are already registered.
    unsigned int actual = 0;
    Class *classes = objc_copyClassList(&actual);
    if (!classes || actual == 0) {
        if (classes) free(classes);
        NSLog(@"[ZZFilterUI] discovery classListUnavailable count=%u", actual);
        return;
    }

    NSUInteger matches = 0;
    NSUInteger broadMatches = 0;
    NSUInteger before = ZZHooked.count;

    for (unsigned int i = 0; i < actual; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        for (unsigned int j = 0; j < methodCount; j++) {
            SEL sel = method_getName(methods[j]);
            NSString *selName = NSStringFromSelector(sel);
            BOOL exact = [names containsObject:selName];
            // The reference exposes these families; tolerate a renamed/private
            // selector in a newer host build while avoiding unrelated methods.
            BOOL broad = [selName hasPrefix:@"addCellWithModel:"] ||
                         [selName hasPrefix:@"addCellsWithModelArray:"] ||
                         [selName hasPrefix:@"insertCellsWithModelArray:"] ||
                         [selName hasPrefix:@"p_addCellsWithModelArray:"] ||
                         [selName hasPrefix:@"p_insertCellsWithModelArray:"] ||
                         [selName hasPrefix:@"reloadListingGoodsWithRespModel:"] ||
                         [selName hasPrefix:@"addListingGoodsWithRespModel:"] ||
                         [selName hasPrefix:@"requestDataWithPageIndex:"] ||
                         [selName hasPrefix:@"setPageIndex:"];
            if (exact || broad) {
                matches++;
                if (broad && !exact) broadMatches++;
                ZZHookClassSelector(cls, sel);
            }
        }
        free(methods);
    }
    free(classes);

    NSLog(@"[ZZFilterUI] discovery classes=%u selectorMatches=%lu broad=%lu newlyHooked=%lu totalHooked=%lu calls=%lu",
          actual, (unsigned long)matches, (unsigned long)broadMatches,
          (unsigned long)(ZZHooked.count - before),
          (unsigned long)ZZHooked.count,
          (unsigned long)ZZCalls);
}
