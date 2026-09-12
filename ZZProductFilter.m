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

static NSString *ZZNormalizeVersion(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRange r = [s rangeOfString:@"iOS" options:NSCaseInsensitiveSearch];
    if (r.location != NSNotFound) s = [s substringFromIndex:NSMaxRange(r)];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d{1,3})(?:\\.(\\d{1,3}))?(?:\\.(\\d{1,3}))?" options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return @"";
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 1; i <= 3; i++) {
        NSRange mr = [m rangeAtIndex:i];
        [parts addObject:(mr.location == NSNotFound ? @"0" : [s substringWithRange:mr])];
    }
    return [parts componentsJoinedByString:@"."];
}

static NSArray<NSNumber *> *ZZVersionComponents(NSString *value) {
    NSString *s = ZZNormalizeVersion(value);
    if (!s.length) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *part in [s componentsSeparatedByString:@"."]) {
        [result addObject:@(ZZNumberFromString(part))];
    }
    while (result.count < 3) [result addObject:@0];
    return result;
}

static NSComparisonResult ZZCompareVersions(NSString *a, NSString *b) {
    NSArray *aa = ZZVersionComponents(a);
    NSArray *bb = ZZVersionComponents(b);
    if (!aa.count || !bb.count) return NSOrderedSame;
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
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) return value;
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *s = [value stringValue];
            if (s.length) return s;
        }
    }
    return @"";
}

static NSString *ZZFindVersionDeep(id obj, NSUInteger depth) {
    if (depth > 4) return @"";
    if ([obj isKindOfClass:NSString.class]) {
        NSString *n = ZZNormalizeVersion(obj);
        return n.length ? n : @"";
    }
    if (![obj isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = obj;
    NSString *direct = ZZFirstString(d, @[@"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"iosVersion", @"systemVersion", @"ios", @"system"]).length ?
        ZZNormalizeVersion(ZZFirstString(d, @[@"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"iosVersion", @"systemVersion", @"ios", @"system"])) : @"";
    if (direct.length) return direct;
    for (NSString *key in d) {
        id value = d[key];
        if ([value isKindOfClass:NSDictionary.class]) {
            NSString *v = ZZFindVersionDeep(value, depth + 1);
            if (v.length) return v;
        }
    }
    return @"";
}

static NSInteger ZZNumberFromProduct(NSDictionary *product) {
    NSArray *priceKeys = @[@"price", @"sellPrice", @"salePrice", @"currentPrice", @"amount", @"saleAmount", @"finalPrice", @"lowestPrice"];
    for (NSString *key in priceKeys) {
        id value = product[key];
        if ([value respondsToSelector:@selector(stringValue)]) {
            NSInteger n = ZZNumberFromString([value stringValue]);
            if (n > 0) return n;
        }
    }
    return 0;
}

- (BOOL)shouldDisplayProduct:(NSDictionary *)product {
    if (!self.enabled || ![product isKindOfClass:NSDictionary.class]) return YES;

    NSInteger numericValue = ZZNumberFromProduct(product);
    if (self.minimumText > 0 && numericValue > 0 && numericValue < self.minimumText) return NO;
    if (self.maximumText < NSIntegerMax && numericValue > 0 && numericValue > self.maximumText) return NO;

    NSString *version = ZZFindVersionDeep(product, 0);
    if (version.length) {
        if (self.minimumVersion.length && ZZCompareVersions(version, self.minimumVersion) == NSOrderedAscending) return NO;
        if (self.maximumVersion.length && ZZCompareVersions(version, self.maximumVersion) == NSOrderedDescending) return NO;
    }
    return YES;
}

- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products {
    if (!self.enabled) return products ?: @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:products.count];
    for (id obj in products ?: @[]) {
        if (![obj isKindOfClass:NSDictionary.class] || [self shouldDisplayProduct:obj]) [result addObject:obj];
    }
    return result;
}

@end
