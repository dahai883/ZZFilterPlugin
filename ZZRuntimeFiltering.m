#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static NSMutableSet<NSString *> *ZZHookedSelectors;
static NSUInteger ZZRuntimeCalls;
static NSUInteger ZZCandidateMatches;
static NSUInteger ZZHookFailures;
static NSUInteger ZZLastScannedClasses;
static NSUInteger ZZLastScannedMethods;
static CFTimeInterval ZZLastScanTime;
static NSUInteger ZZResponseObjects;
static NSUInteger ZZResponseArrays;
static NSUInteger ZZResponseDictionaries;
static NSUInteger ZZResponseUnknown;

static NSArray *ZZFilteredArray(NSArray *models, NSString *selectorName) {
    ZZRuntimeCalls += 1;
    if (!ZZSettings.shared.enabled || ![models isKindOfClass:NSArray.class]) return models;
    NSArray *filtered = ZZFilteredModels(models);
    if (filtered != models) {
        NSLog(@"[ZZFilterUI] runtime selector=%@ array=%lu -> %lu",
              selectorName, (unsigned long)models.count, (unsigned long)filtered.count);
    }
    return filtered;
}

static NSString *ZZHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%p:%@", cls, NSStringFromSelector(selector)];
}

// These entry points are ordinary Objective-C methods with object-array/list
// arguments. Using typed IMP blocks avoids objc_msgForward, which is not
// exported to all iOS dylib link environments (especially arm64e).
static IMP ZZMakeAddCells3(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className) {
        NSArray *f = ZZFilteredArray(models, @"addCellsWithModelArray:forSection:className:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *))original)(self, @selector(addCellsWithModelArray:forSection:className:), f, section, className);
    });
}

static IMP ZZMakeAddCells4(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className, id tag) {
        NSArray *f = ZZFilteredArray(models, @"addCellsWithModelArray:forSection:className:tag:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *, id))original)(self, @selector(addCellsWithModelArray:forSection:className:tag:), f, section, className, tag);
    });
}

static IMP ZZMakeInsertCells4(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className, NSInteger pos) {
        NSArray *f = ZZFilteredArray(models, @"insertCellsWithModelArray:forSection:className:pos:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *, NSInteger))original)(self, @selector(insertCellsWithModelArray:forSection:className:pos:), f, section, className, pos);
    });
}

static IMP ZZMakeInsertCells5(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className, id tag, NSInteger pos) {
        NSArray *f = ZZFilteredArray(models, @"insertCellsWithModelArray:forSection:className:tag:pos:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *, id, NSInteger))original)(self, @selector(insertCellsWithModelArray:forSection:className:tag:pos:), f, section, className, tag, pos);
    });
}

static IMP ZZMakePAddCells4(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className, id tag) {
        NSArray *f = ZZFilteredArray(models, @"p_addCellsWithModelArray:forSection:className:tag:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *, id))original)(self, @selector(p_addCellsWithModelArray:forSection:className:tag:), f, section, className, tag);
    });
}

static IMP ZZMakePInsertCells5(IMP original) {
    return imp_implementationWithBlock(^(id self, NSArray *models, NSInteger section, NSString *className, id tag, NSInteger pos) {
        NSArray *f = ZZFilteredArray(models, @"p_insertCellsWithModelArray:forSection:className:tag:pos:");
        ((void (*)(id, SEL, NSArray *, NSInteger, NSString *, id, NSInteger))original)(self, @selector(p_insertCellsWithModelArray:forSection:className:tag:pos:), f, section, className, tag, pos);
    });
}

static IMP ZZMakeListingResponse(IMP original) {
    return imp_implementationWithBlock(^(id self, id response) {
        ZZRuntimeCalls += 1;
        // The response object may itself expose a product/model array. Keep
        // this hook observational unless ZZFilterRenderedData can recognize
        // the concrete shape; the normal model-array hooks do the filtering.
        ZZResponseObjects += 1;
        if ([response isKindOfClass:NSArray.class]) ZZResponseArrays += 1;
        else if ([response isKindOfClass:NSDictionary.class]) ZZResponseDictionaries += 1;
        else ZZResponseUnknown += 1;
        NSLog(@"[ZZFilterUI] response hook selector=addListingGoodsWithRespModel class=%@", response ? NSStringFromClass([response class]) : @"(nil)");
        ZZResponseObjects += 1;
        if ([response isKindOfClass:NSArray.class]) ZZResponseArrays += 1;
        else if ([response isKindOfClass:NSDictionary.class]) ZZResponseDictionaries += 1;
        else ZZResponseUnknown += 1;
        NSLog(@"[ZZFilterUI] response hook selector=reloadListingGoodsWithRespModel class=%@", response ? NSStringFromClass([response class]) : @"(nil)");
        id value = response;
        id filtered = ZZFilterRenderedData(value);
        if (filtered && filtered != value) value = filtered;
        ((void (*)(id, SEL, id))original)(self, @selector(addListingGoodsWithRespModel:), value);
    });
}

static IMP ZZMakeReloadResponse(IMP original) {
    return imp_implementationWithBlock(^(id self, id response) {
        ZZRuntimeCalls += 1;
        id value = response;
        id filtered = ZZFilterRenderedData(value);
        if (filtered && filtered != value) value = filtered;
        ((void (*)(id, SEL, id))original)(self, @selector(reloadListingGoodsWithRespModel:), value);
    });
}

static IMP ZZBuildWrapperForSelector(SEL selector, IMP original) {
    NSString *name = NSStringFromSelector(selector);
    if ([name isEqualToString:@"addCellsWithModelArray:forSection:className:"]) return ZZMakeAddCells3(original);
    if ([name isEqualToString:@"addCellsWithModelArray:forSection:className:tag:"]) return ZZMakeAddCells4(original);
    if ([name isEqualToString:@"insertCellsWithModelArray:forSection:className:pos:"]) return ZZMakeInsertCells4(original);
    if ([name isEqualToString:@"insertCellsWithModelArray:forSection:className:tag:pos:"]) return ZZMakeInsertCells5(original);
    if ([name isEqualToString:@"p_addCellsWithModelArray:forSection:className:tag:"]) return ZZMakePAddCells4(original);
    if ([name isEqualToString:@"p_insertCellsWithModelArray:forSection:className:tag:pos:"]) return ZZMakePInsertCells5(original);
    if ([name isEqualToString:@"addListingGoodsWithRespModel:"]) return ZZMakeListingResponse(original);
    if ([name isEqualToString:@"reloadListingGoodsWithRespModel:"]) return ZZMakeReloadResponse(original);
    return NULL;
}

static BOOL ZZHookSelector(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSString *key = ZZHookKey(cls, selector);
    if ([ZZHookedSelectors containsObject:key]) return YES;

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);
    IMP wrapper = ZZBuildWrapperForSelector(selector, original);
    if (!wrapper) { ZZHookFailures += 1; return NO; }

    // Guard against an unexpected ABI. The expected methods are void-returning
    // and have only object/integer arguments. If an app update changes the
    // signature, leave the method untouched instead of risking a crash.
    NSUInteger args = method_getNumberOfArguments(method);
    if (args < 3 || args > 7 || !types || types[0] != 'v') {
        ZZHookFailures += 1;
        NSLog(@"[ZZFilterUI] skip unexpected signature %@ %@ encoding=%s",
              NSStringFromClass(cls), NSStringFromSelector(selector), types ?: "(null)");
        return NO;
    }

    method_setImplementation(method, wrapper);
    [ZZHookedSelectors addObject:key];
    NSLog(@"[ZZFilterUI] hooked %@ %@ encoding=%s",
          NSStringFromClass(cls), NSStringFromSelector(selector), types);
    return YES;
}

NSUInteger ZZRuntimeFilteringHookCount(void) { return ZZHookedSelectors.count; }
NSUInteger ZZRuntimeFilteringCalls(void) { return ZZRuntimeCalls; }
NSUInteger ZZRuntimeFilteringCandidateCount(void) { return ZZCandidateMatches; }
NSUInteger ZZRuntimeFilteringHookFailureCount(void) { return ZZHookFailures; }
NSUInteger ZZRuntimeFilteringScannedClasses(void) { return ZZLastScannedClasses; }
NSUInteger ZZRuntimeFilteringScannedMethods(void) { return ZZLastScannedMethods; }
NSUInteger ZZRuntimeFilteringResponseObjects(void) { return ZZResponseObjects; }
NSUInteger ZZRuntimeFilteringResponseArrays(void) { return ZZResponseArrays; }
NSUInteger ZZRuntimeFilteringResponseDictionaries(void) { return ZZResponseDictionaries; }
NSUInteger ZZRuntimeFilteringResponseUnknown(void) { return ZZResponseUnknown; }

void ZZInstallRuntimeFiltering(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZZHookedSelectors = [NSMutableSet set];
    });

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;

    CFTimeInterval now = CACurrentMediaTime();
    // Avoid rescanning ~70k methods every second forever. Re-scan when the
    // runtime grows, or periodically while no hook has been installed yet.
    if (ZZHookedSelectors.count > 0 && (NSUInteger)classCount == ZZLastScannedClasses) return;
    if (ZZHookedSelectors.count == 0 && (now - ZZLastScanTime) < 2.0 && (NSUInteger)classCount == ZZLastScannedClasses) return;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    int actual = objc_getClassList(classes, classCount);
    NSUInteger methodsSeen = 0;
    NSUInteger candidatesThisScan = 0;

    NSSet *targets = [NSSet setWithArray:@[
        @"addCellsWithModelArray:forSection:className:",
        @"addCellsWithModelArray:forSection:className:tag:",
        @"insertCellsWithModelArray:forSection:className:pos:",
        @"insertCellsWithModelArray:forSection:className:tag:pos:",
        @"p_addCellsWithModelArray:forSection:className:tag:",
        @"p_insertCellsWithModelArray:forSection:className:tag:pos:",
        @"addListingGoodsWithRespModel:",
        @"reloadListingGoodsWithRespModel:"
    ]];

    for (int i = 0; i < actual; i++) {
        Class cls = classes[i];
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        if (!methods) continue;
        methodsSeen += count;
        for (unsigned int m = 0; m < count; m++) {
            SEL sel = method_getName(methods[m]);
            if (![targets containsObject:NSStringFromSelector(sel)]) continue;
            candidatesThisScan += 1;
            ZZCandidateMatches += 1;
            NSLog(@"[ZZFilterUI] candidate class=%@ selector=%@", NSStringFromClass(cls), NSStringFromSelector(sel));
            ZZHookSelector(cls, sel);
        }
        free(methods);
    }
    free(classes);

    ZZLastScannedClasses = (NSUInteger)actual;
    ZZLastScannedMethods = methodsSeen;
    ZZLastScanTime = now;
    NSLog(@"[ZZFilterUI] runtime discovery v5: classes=%d methods=%lu candidates=%lu totalCandidates=%lu hookFailures=%lu totalHooked=%lu",
          actual, (unsigned long)methodsSeen, (unsigned long)candidatesThisScan,
          (unsigned long)ZZCandidateMatches, (unsigned long)ZZHookFailures,
          (unsigned long)ZZHookedSelectors.count);
}
