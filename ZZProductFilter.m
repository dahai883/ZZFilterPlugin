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

static NSString *ZZNormalizeVersion(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *s = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?i)^(?:iOS\\s*)?(\\d{1,3})(?:\\.(\\d{1,3}))?(?:\\.(\\d{1,3}))?\\s*$" options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return @"";
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 1; i <= 3; i++) {
        NSRange r = [m rangeAtIndex:i];
        [parts addObject:(r.location == NSNotFound ? @"0" : [s substringWithRange:r])];
    }
    return [parts componentsJoinedByString:@"."];
}

static NSArray<NSNumber *> *ZZVersionComponents(NSString *value) {
    NSString *s = ZZNormalizeVersion(value);
    if (!s.length) return @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:3];
    for (NSString *part in [s componentsSeparatedByString:@"."]) {
        [result addObject:@(part.integerValue)];
    }
    while (result.count < 3) [result addObject:@0];
    return result;
}

static NSComparisonResult ZZCompareVersions(NSString *a, NSString *b) {
    NSArray *aa = ZZVersionComponents(a);
    NSArray *bb = ZZVersionComponents(b);
    if (!aa.count || !bb.count) return NSOrderedSame;
    for (NSUInteger i = 0; i < 3; i++) {
        NSInteger av = [aa[i] integerValue];
        NSInteger bv = [bb[i] integerValue];
        if (av < bv) return NSOrderedAscending;
        if (av > bv) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

// Version is the only product attribute used by V14's primary filter.
// Accept the common Zhuanzhuan field spellings and nested dictionaries.
static NSString *ZZFindVersionDeep(id obj, NSUInteger depth) {
    if (depth > 5 || !obj) return @"";
    if ([obj isKindOfClass:NSString.class]) return ZZNormalizeVersion(obj);
    if (![obj isKindOfClass:NSDictionary.class]) return @"";

    NSDictionary *d = (NSDictionary *)obj;
    NSArray *keys = @[@"iosVersion", @"systemVersion", @"iOSVersion", @"ios", @"system", @"version", @"modelVersion", @"goodsVersion", @"waresVersion"];
    for (NSString *key in keys) {
        id value = d[key];
        if ([value isKindOfClass:NSString.class]) {
            NSString *v = ZZNormalizeVersion(value);
            if (v.length) return v;
        } else if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *v = ZZNormalizeVersion([value stringValue]);
            if (v.length) return v;
        }
    }

    // Prefer objects whose key names suggest device/detail/system information.
    for (NSString *key in d) {
        NSString *lower = key.lowercaseString;
        if (![lower containsString:@"ios"] && ![lower containsString:@"system"] && ![lower containsString:@"detail"] && ![lower containsString:@"info"]) continue;
        NSString *v = ZZFindVersionDeep(d[key], depth + 1);
        if (v.length) return v;
    }
    for (NSString *key in d) {
        id value = d[key];
        if ([value isKindOfClass:NSDictionary.class]) {
            NSString *v = ZZFindVersionDeep(value, depth + 1);
            if (v.length) return v;
        }
    }
    return @"";
}

NSString *ZZProductVersionFromDictionary(NSDictionary *product) {
    return ZZFindVersionDeep(product, 0);
}

- (BOOL)shouldDisplayProduct:(NSDictionary *)product {
    if (!self.enabled || ![product isKindOfClass:NSDictionary.class]) return YES;
    if (!self.minimumVersion.length && !self.maximumVersion.length) return YES;

    NSString *version = ZZFindVersionDeep(product, 0);
    // Unknown version is kept. This prevents the plugin from hiding listings
    // merely because their list payload does not carry the detail fields.
    if (!version.length) return YES;

    if (self.minimumVersion.length && ZZCompareVersions(version, self.minimumVersion) == NSOrderedAscending) return NO;
    if (self.maximumVersion.length && ZZCompareVersions(version, self.maximumVersion) == NSOrderedDescending) return NO;
    return YES;
}

- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products {
    if (!self.enabled || (!self.minimumVersion.length && !self.maximumVersion.length)) return products ?: @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:products.count];
    for (id obj in products ?: @[]) {
        if (![obj isKindOfClass:NSDictionary.class] || [self shouldDisplayProduct:obj]) [result addObject:obj];
    }
    return result;
}

@end
