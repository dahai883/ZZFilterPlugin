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
    if ([scanner scanInteger:&number]) return number;
    return 0;
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
    NSUInteger count = MAX(aa.count, bb.count);
    for (NSUInteger i = 0; i < count; i++) {
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
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) return value;
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *s = [value stringValue];
            if (s.length > 0) return s;
        }
    }
    return @"";
}

static NSInteger ZZNumberFromProduct(NSDictionary *product) {
    // Prefer explicit price/amount fields. This avoids interpreting a model
    // number such as "iPhone 15 Pro Max" as the numeric filter value.
    NSArray *priceKeys = @[@"price", @"sellPrice", @"salePrice", @"currentPrice",
                           @"amount", @"saleAmount", @"finalPrice", @"lowestPrice"];
    for (NSString *key in priceKeys) {
        id value = product[key];
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSInteger n = ZZNumberFromString([value stringValue]);
            if (n > 0) return n;
        }
    }
    NSString *text = ZZFirstString(product, @[@"text", @"name", @"title"]);
    return ZZNumberFromString(text);
}

- (BOOL)shouldDisplayProduct:(NSDictionary *)product {
    if (!self.enabled) return YES;
    if (![product isKindOfClass:NSDictionary.class]) return YES;

    NSInteger numericValue = ZZNumberFromProduct(product);
    if (self.minimumText > 0 && numericValue > 0 && numericValue < self.minimumText) return NO;
    if (self.maximumText < NSIntegerMax && numericValue > 0 && numericValue > self.maximumText) return NO;

    NSString *version = ZZFirstString(product, @[
        @"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"iosVersion", @"systemVersion"
    ]);
    if (version.length > 0) {
        if (self.minimumVersion.length > 0 &&
            ZZCompareVersions(version, self.minimumVersion) == NSOrderedAscending) return NO;
        if (self.maximumVersion.length > 0 &&
            ZZCompareVersions(version, self.maximumVersion) == NSOrderedDescending) return NO;
    }
    return YES;
}

- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products {
    if (!self.enabled) return products ?: @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:products.count];
    for (id obj in products ?: @[]) {
        if (![obj isKindOfClass:NSDictionary.class] || [self shouldDisplayProduct:obj]) {
            if ([obj isKindOfClass:NSDictionary.class]) [result addObject:obj];
        }
    }
    return result;
}

@end
