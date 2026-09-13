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

static BOOL ZZLooksLikeSystemVersionLabel(NSString *key) {
    if (![key isKindOfClass:NSString.class]) return NO;
    NSString *k = key.lowercaseString;
    return [k containsString:@"ios"] ||
           [k containsString:@"systemversion"] ||
           [k containsString:@"system_version"] ||
           [k containsString:@"system version"] ||
           [k containsString:@"系统版本"] ||
           [k containsString:@"系统版本号"] ||
           [k containsString:@"ios版本"] ||
           [k containsString:@"ios版本号"] ||
           [k containsString:@"os版本"];
}

static BOOL ZZStringContainsIOSMarker(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *s = value.lowercaseString;
    return [s containsString:@"ios"];
}

// Extract only the actual iOS/system-version attribute. V15 accidentally
// preferred the generic `version` field, which is commonly the app/model
// version (1.0.0). V16 deliberately gives system-version-labelled fields and
// key/value attribute pairs priority and ignores an unlabelled generic 1.0.0.
static NSString *ZZFindVersionDeep(id obj, NSUInteger depth) {
    if (depth > 8 || !obj) return @"";
    if ([obj isKindOfClass:NSString.class]) return ZZStringContainsIOSMarker(obj) ? ZZNormalizeVersion(obj) : @"";
    if (![obj isKindOfClass:NSDictionary.class]) return @"";

    NSDictionary *d = (NSDictionary *)obj;

    // Common direct system-version fields. Never let generic `version` win first.
    NSArray *priorityKeys = @[@"iosVersion", @"iOSVersion", @"systemVersion", @"system_version", @"ios_version", @"ios", @"system"];
    for (NSString *key in priorityKeys) {
        id value = d[key];
        if ([value isKindOfClass:NSString.class]) {
            NSString *v = ZZNormalizeVersion(value);
            if (v.length) return v;
        } else if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *v = ZZNormalizeVersion([value stringValue]);
            if (v.length) return v;
        }
    }

    // Zhuanzhuan detail attributes often arrive as {key: "系统版本", value: "iOS 26.4.1"}.
    id label = d[@"key"] ?: d[@"name"] ?: d[@"attrName"] ?: d[@"attributeName"] ?: d[@"title"];
    id value = d[@"value"] ?: d[@"attrValue"] ?: d[@"attributeValue"] ?: d[@"content"];
    if ([label isKindOfClass:NSString.class] && ZZLooksLikeSystemVersionLabel(label)) {
        if ([value isKindOfClass:NSString.class]) {
            NSString *v = ZZNormalizeVersion(value);
            if (v.length) return v;
        } else if ([value respondsToSelector:@selector(stringValue)]) {
            NSString *v = ZZNormalizeVersion([value stringValue]);
            if (v.length) return v;
        }
    }

    // Some payloads use arbitrary attribute names but put the literal iOS marker
    // in the value. Accept those only from value/content-style fields, not generic
    // `version`, so 1.0.0 is never mistaken for the system version.
    for (NSString *key in @[@"value", @"attrValue", @"attributeValue", @"content", @"text", @"displayValue"]) {
        id candidate = d[key];
        if ([candidate isKindOfClass:NSString.class] && ZZStringContainsIOSMarker(candidate)) {
            NSString *v = ZZNormalizeVersion(candidate);
            if (v.length) return v;
        }
    }

    // Recurse through system/detail-labelled branches first.
    for (NSString *key in d) {
        if (!ZZLooksLikeSystemVersionLabel(key) && ![key.lowercaseString containsString:@"detail"] && ![key.lowercaseString containsString:@"attr"]) continue;
        NSString *v = ZZFindVersionDeep(d[key], depth + 1);
        if (v.length) return v;
    }
    for (NSString *key in d) {
        id child = d[key];
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
            NSString *v = ZZFindVersionDeep(child, depth + 1);
            if (v.length) return v;
        }
    }

    // Generic version/modelVersion/etc. are intentionally NOT treated as iOS
    // version unless their value explicitly contains the iOS marker.
    for (NSString *key in @[@"version", @"modelVersion", @"goodsVersion", @"waresVersion"]) {
        id candidate = d[key];
        if ([candidate isKindOfClass:NSString.class] && ZZStringContainsIOSMarker(candidate)) {
            NSString *v = ZZNormalizeVersion(candidate);
            if (v.length) return v;
        }
    }
    return @"";
}

NSString *ZZProductVersionFromDictionary(NSDictionary *product) {
    return ZZFindVersionDeep(product, 0);
}

static NSArray<NSNumber *> *ZZVersionComponents(NSString *value) {
    NSString *s = ZZNormalizeVersion(value);
    if (!s.length) return @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:3];
    for (NSString *part in [s componentsSeparatedByString:@"."]) [result addObject:@(part.integerValue)];
    while (result.count < 3) [result addObject:@0];
    return result;
}

static NSComparisonResult ZZCompareVersions(NSString *a, NSString *b) {
    NSArray *aa = ZZVersionComponents(a), *bb = ZZVersionComponents(b);
    if (!aa.count || !bb.count) return NSOrderedSame;
    for (NSUInteger i = 0; i < 3; i++) {
        NSInteger av = [aa[i] integerValue], bv = [bb[i] integerValue];
        if (av < bv) return NSOrderedAscending;
        if (av > bv) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)shouldDisplayProduct:(NSDictionary *)product {
    if (!self.enabled || ![product isKindOfClass:NSDictionary.class]) return YES;
    if (!self.minimumVersion.length && !self.maximumVersion.length) return YES;
    NSString *version = ZZFindVersionDeep(product, 0);
    if (!version.length) return YES;
    if (self.minimumVersion.length && ZZCompareVersions(version, self.minimumVersion) == NSOrderedAscending) return NO;
    if (self.maximumVersion.length && ZZCompareVersions(version, self.maximumVersion) == NSOrderedDescending) return NO;
    return YES;
}

- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products {
    if (!self.enabled || (!self.minimumVersion.length && !self.maximumVersion.length)) return products ?: @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:products.count];
    for (id obj in products ?: @[]) if (![obj isKindOfClass:NSDictionary.class] || [self shouldDisplayProduct:obj]) [result addObject:obj];
    return result;
}

@end
