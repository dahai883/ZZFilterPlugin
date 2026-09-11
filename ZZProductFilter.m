#import "ZZProductFilter.h"

@implementation ZZProductFilter

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _minimumText = 0;
        _maximumText = NSIntegerMax;
        _minimumVersion = @"";
        _maximumVersion = @"";
    }
    return self;
}

static NSInteger ZZNumberFromString(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger number = 0;
    [scanner scanInteger:&number];
    return number;
}

static NSArray<NSNumber *> *ZZVersionComponents(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByString:@"."]) {
        [result addObject:@(ZZNumberFromString(part))];
    }
    while (result.count < 4) [result addObject:@0];
    return result;
}

static NSComparisonResult ZZCompareVersions(NSString *a, NSString *b) {
    NSArray *aa = ZZVersionComponents(a);
    NSArray *bb = ZZVersionComponents(b);
    for (NSUInteger i = 0; i < MAX(aa.count, bb.count); i++) {
        NSInteger av = i < aa.count ? [aa[i] integerValue] : 0;
        NSInteger bv = i < bb.count ? [bb[i] integerValue] : 0;
        if (av < bv) return NSOrderedAscending;
        if (av > bv) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

static NSString *ZZFirstString(NSDictionary *d, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = d[key];
        if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
        if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    }
    return @"";
}

- (BOOL)shouldDisplayProduct:(NSDictionary *)product {
    if (!self.enabled) return YES;
    if (![product isKindOfClass:NSDictionary.class]) return YES;

    NSString *textValue = ZZFirstString(product, @[
        @"text", @"name", @"title", @"price", @"minimumText", @"maximumText"
    ]);
    NSInteger numericText = ZZNumberFromString(textValue);

    if (self.minimumText > 0 && numericText > 0 && numericText < self.minimumText) {
        return NO;
    }
    if (self.maximumText < NSIntegerMax && numericText > 0 && numericText > self.maximumText) {
        return NO;
    }

    NSString *version = ZZFirstString(product, @[
        @"version", @"modelVersion", @"goodsVersion", @"waresVersion"
    ]);

    if (version.length > 0) {
        if (self.minimumVersion.length > 0 &&
            ZZCompareVersions(version, self.minimumVersion) == NSOrderedAscending) {
            return NO;
        }
        if (self.maximumVersion.length > 0 &&
            ZZCompareVersions(version, self.maximumVersion) == NSOrderedDescending) {
            return NO;
        }
    }

    return YES;
}

- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products {
    if (!self.enabled) return products ?: @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id obj in products ?: @[]) {
        if ([obj isKindOfClass:NSDictionary.class] && [self shouldDisplayProduct:obj]) {
            [result addObject:obj];
        }
    }
    return result;
}

@end
