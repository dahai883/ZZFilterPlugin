#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"
#import "ZZDebug.h"
#import <objc/runtime.h>

// Targeted hooks only: no global class/method enumeration. This follows the
// concrete listing selectors observed in the reference binary while avoiding
// the v11 full-runtime scan that caused high CPU/watchdog failures.
static NSUInteger ZZRuntimeHooks = 0;
static NSUInteger ZZRuntimeCalls = 0;
static NSUInteger ZZRuntimeCandidates = 0;

static NSObject *ZZRuntimeLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static IMP gAddCell3 = NULL;
static IMP gAddCell4 = NULL;
static IMP gAddCells3 = NULL;
static IMP gAddCells4 = NULL;
static IMP gInsertCells4 = NULL;
static IMP gInsertCells5 = NULL;
static IMP gPrivateAddCells4 = NULL;
static IMP gPrivateInsertCells5 = NULL;
static IMP gReloadListingGoods = NULL;
static IMP gAddListingGoods = NULL;
static IMP gRequestPage = NULL;

static Class gRequestPageClass = Nil;
static const char *gRequestPageTypeEncoding = NULL;

static BOOL ZZClassMatchesKnown(Class cls) {
    if (!cls) return NO;
    NSString *name = NSStringFromClass(cls);
    return [name isEqualToString:@"ZZListingAprilViewController"] ||
           [name isEqualToString:@"ZZFlexibleLayoutViewController"];
}

static NSArray<Class> *ZZKnownListingClasses(void) {
    NSMutableArray<Class> *result = [NSMutableArray arrayWithCapacity:2];
    for (NSString *name in @[@"ZZListingAprilViewController", @"ZZFlexibleLayoutViewController"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (cls && ![result containsObject:cls]) [result addObject:cls];
    }
    return result.copy;
}

static BOOL ZZInstallOne(Class cls, SEL sel, IMP replacement, IMP *originalOut) {
    if (!cls || !sel || !replacement || !originalOut || *originalOut) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_getImplementation(m);
    const char *types = method_getTypeEncoding(m);
    if (!old || !types || old == replacement) return NO;

    // If the selector is inherited, add a subclass implementation instead of
    // mutating the superclass globally. This keeps the hook narrowly scoped.
    Method own = class_getInstanceMethod(cls, sel);
    BOOL owns = class_getInstanceMethod(cls, sel) && class_getMethodImplementation(cls, sel) == old;
    (void)own;
    if (class_addMethod(cls, sel, replacement, types)) {
        *originalOut = old;
        ZZRuntimeHooks += 1;
        return YES;
    }
    if (owns) {
        method_setImplementation(m, replacement);
        *originalOut = old;
        ZZRuntimeHooks += 1;
        return YES;
    }
    // class_addMethod can fail because the class has its own implementation;
    // class_getInstanceMethod then safely refers to the class-local Method.
    method_setImplementation(m, replacement);
    *originalOut = old;
    ZZRuntimeHooks += 1;
    return YES;
}

static BOOL ZZKeep(id model) {
    ZZRuntimeCalls += 1;
    BOOL keep = ZZShouldKeepModel(model);
    if (!keep) ZZRuntimeCandidates += 1;
    return keep;
}

static void ZZAddCell3(id self, SEL _cmd, id model, NSInteger section, id className) {
    if (!ZZKeep(model)) return;
    ((void (*)(id,SEL,id,NSInteger,id))gAddCell3)(self,_cmd,model,section,className);
}
static void ZZAddCell4(id self, SEL _cmd, id model, NSInteger section, id className, id tag) {
    if (!ZZKeep(model)) return;
    ((void (*)(id,SEL,id,NSInteger,id,id))gAddCell4)(self,_cmd,model,section,className,tag);
}
static void ZZAddCells3(id self, SEL _cmd, NSArray *models, NSInteger section, id className) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id))gAddCells3)(self,_cmd,filtered,section,className);
}
static void ZZAddCells4(id self, SEL _cmd, NSArray *models, NSInteger section, id className, id tag) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id,id))gAddCells4)(self,_cmd,filtered,section,className,tag);
}
static void ZZInsertCells4(id self, SEL _cmd, NSArray *models, NSInteger section, id className, NSInteger pos) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id,NSInteger))gInsertCells4)(self,_cmd,filtered,section,className,pos);
}
static void ZZInsertCells5(id self, SEL _cmd, NSArray *models, NSInteger section, id className, id tag, NSInteger pos) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id,id,NSInteger))gInsertCells5)(self,_cmd,filtered,section,className,tag,pos);
}
static void ZZPrivateAddCells4(id self, SEL _cmd, NSArray *models, NSInteger section, id className, id tag) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id,id))gPrivateAddCells4)(self,_cmd,filtered,section,className,tag);
}
static void ZZPrivateInsertCells5(id self, SEL _cmd, NSArray *models, NSInteger section, id className, id tag, NSInteger pos) {
    NSArray *filtered = ZZFilteredModels(models);
    ((void (*)(id,SEL,NSArray*,NSInteger,id,id,NSInteger))gPrivateInsertCells5)(self,_cmd,filtered,section,className,tag,pos);
}
static void ZZReloadListingGoods(id self, SEL _cmd, id responseModel) {
    id filtered = ZZFilterRenderedData(responseModel);
    ((void (*)(id,SEL,id))gReloadListingGoods)(self,_cmd,filtered);
}
static void ZZAddListingGoods(id self, SEL _cmd, id responseModel) {
    id filtered = ZZFilterRenderedData(responseModel);
    ((void (*)(id,SEL,id))gAddListingGoods)(self,_cmd,filtered);
}
static void ZZRequestPage(id self, SEL _cmd, NSInteger pageIndex) {
    ZZRuntimeCalls += 1;
    ((void (*)(id,SEL,NSInteger))gRequestPage)(self,_cmd,pageIndex);
}

void ZZInstallRuntimeFiltering(void) {
    @synchronized (ZZRuntimeLock()) {
        NSArray<Class> *classes = ZZKnownListingClasses();
        if (!classes.count) {
            ZZFilterDebugWrite(@"[ZZFilterUI] v26 known listing controllers not loaded yet");
            return;
        }

        for (Class cls in classes) {
            if (!gAddCell3) ZZInstallOne(cls, @selector(addCellWithModel:forSection:className:), (IMP)ZZAddCell3, &gAddCell3);
            if (!gAddCell4) ZZInstallOne(cls, @selector(addCellWithModel:forSection:className:tag:), (IMP)ZZAddCell4, &gAddCell4);
            if (!gAddCells3) ZZInstallOne(cls, @selector(addCellsWithModelArray:forSection:className:), (IMP)ZZAddCells3, &gAddCells3);
            if (!gAddCells4) ZZInstallOne(cls, @selector(addCellsWithModelArray:forSection:className:tag:), (IMP)ZZAddCells4, &gAddCells4);
            if (!gInsertCells4) ZZInstallOne(cls, @selector(insertCellsWithModelArray:forSection:className:pos:), (IMP)ZZInsertCells4, &gInsertCells4);
            if (!gInsertCells5) ZZInstallOne(cls, @selector(insertCellsWithModelArray:forSection:className:tag:pos:), (IMP)ZZInsertCells5, &gInsertCells5);
            if (!gPrivateAddCells4) ZZInstallOne(cls, @selector(p_addCellsWithModelArray:forSection:className:tag:), (IMP)ZZPrivateAddCells4, &gPrivateAddCells4);
            if (!gPrivateInsertCells5) ZZInstallOne(cls, @selector(p_insertCellsWithModelArray:forSection:className:tag:pos:), (IMP)ZZPrivateInsertCells5, &gPrivateInsertCells5);
            if (!gReloadListingGoods) ZZInstallOne(cls, @selector(reloadListingGoodsWithRespModel:), (IMP)ZZReloadListingGoods, &gReloadListingGoods);
            if (!gAddListingGoods) ZZInstallOne(cls, @selector(addListingGoodsWithRespModel:), (IMP)ZZAddListingGoods, &gAddListingGoods);
            if (!gRequestPage) {
                Method m = class_getInstanceMethod(cls, @selector(requestDataWithPageIndex:));
                if (m) {
                    gRequestPageClass = cls;
                    gRequestPageTypeEncoding = method_getTypeEncoding(m);
                    ZZInstallOne(cls, @selector(requestDataWithPageIndex:), (IMP)ZZRequestPage, &gRequestPage);
                }
            }
        }
        ZZFilterDebugWrite(@"[ZZFilterUI] v26 targeted hooks installed=%lu classes=%lu", (unsigned long)ZZRuntimeHooks, (unsigned long)classes.count);
    }
}

NSUInteger ZZRuntimeFilteringHookCount(void) { return ZZRuntimeHooks; }
NSUInteger ZZRuntimeFilteringCalls(void) { return ZZRuntimeCalls; }
NSUInteger ZZRuntimeCandidateCount(void) { return ZZRuntimeCandidates; }
NSString *ZZRuntimeDiagnosticSummary(void) {
    return [NSString stringWithFormat:@"v26 targeted listing hooks=%lu", (unsigned long)ZZRuntimeHooks];
}

static IMP ZZResolvePageIMP(id controller, SEL sel) {
    if (!controller || !sel) return NULL;
    Class cls = object_getClass(controller);
    while (cls) {
        Method m = class_getInstanceMethod(cls, sel);
        if (m) return method_getImplementation(m);
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

void ZZRequestAdditionalListingPages(id controller, NSUInteger count) {
    if (!controller || count == 0) return;
    SEL sel = @selector(requestDataWithPageIndex:);
    if (![controller respondsToSelector:sel]) return;

    NSInteger current = 1;
    @try {
        id value = [controller valueForKey:@"pageIndex"];
        if ([value respondsToSelector:@selector(integerValue)]) current = [value integerValue];
    } @catch (__unused NSException *e) {}
    if (current < 1) current = 1;

    // Do not hard-cap the result set at 20. A click requests another bounded
    // batch for stability; the user can continue tapping "加载更多".
    NSUInteger pages = MIN(count, (NSUInteger)5);
    for (NSUInteger i = 1; i <= pages; i++) {
        NSInteger page = current + (NSInteger)i;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![controller respondsToSelector:sel]) return;
            IMP imp = gRequestPage ?: ZZResolvePageIMP(controller, sel);
            if (!imp) return;
            ((void (*)(id,SEL,NSInteger))imp)(controller, sel, page);
            ZZFilterDebugWrite(@"[ZZFilterUI] requested additional listing page=%ld", (long)page);
        });
    }
}
