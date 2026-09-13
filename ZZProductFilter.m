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
    if (!s.length) return @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?i)^(?:ios|iPhone\s*OS|os)\\s*[:：-]?\\s*(\\d{1,3})(?:\\.(\\d{1,3}))?(?:\\.(\\d{1,3}))?\\s*$" options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) {
        re = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{1,3})(?:\\.(\\d{1,3}))?(?:\\.(\\d{1,3}))?$" options:0 error:NULL];
        m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    }
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
           [k containsString:@"iphoneos"] ||
           [k containsString:@"systemversion"] ||
           [k containsString:@"system_version"] ||
           [k containsString:@"system version"] ||
           [k containsString:@"系统版本"] ||
           [k containsString:@"系统版本号"] ||
           ([k containsString:@"系统"] && [k containsString:@"版本"]) ||
           [k containsString:@"ios版本"] ||
           [k containsString:@"ios版本号"] ||
           [k containsString:@"os版本"] ||
           [k isEqualToString:@"os"];
}

static NSString *ZZExtractVersionFromText(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return @"";

    // Explicit iOS/iPhone OS marker is always safe to accept.
    NSRegularExpression *iosRe = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\b(?:ios|iphone\\s*os|ipad\\s*os)\\s*(?:版本|version)?\\s*[:：-]?\\s*(\\d{1,3}(?:\\.\\d{1,3}){0,2})\\b" options:0 error:NULL];
    NSTextCheckingResult *m = [iosRe firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (m) {
        NSRange r = [m rangeAtIndex:1];
        if (r.location != NSNotFound) return ZZNormalizeVersion([value substringWithRange:r]);
    }

    // Detail payloads sometimes flatten the Chinese label and numeric value.
    NSRegularExpression *cnRe = [NSRegularExpression regularExpressionWithPattern:@"(?:系统版本(?:号)?|系统\\s*版本|OS版本)\\s*[:：=]?\\s*(?:iOS\\s*)?(\\d{1,3}(?:\\.\\d{1,3}){0,2})" options:NSRegularExpressionCaseInsensitive error:NULL];
    m = [cnRe firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (m) {
        NSRange r = [m rangeAtIndex:1];
        if (r.location != NSNotFound) return ZZNormalizeVersion([value substringWithRange:r]);
    }
    return @"";
}

static BOOL ZZStringContainsIOSMarker(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *s = value.lowercaseString;
    return [s containsString:@"ios"] || [s containsString:@"iphone os"] || [s containsString:@"ipad os"];
}

// Deep extraction is deliberately conservative for generic `version=1.0.0`,
// but broad for the real system-version attribute. v28 additionally handles
// the response shapes observed in detail payloads: params arrays, nested
// key/value objects, flattened text, and numeric values under a system label.
static NSString *ZZFindVersionDeep(id obj, NSUInteger depth) {
    if (depth > 14 || !obj) return @"";

    if ([obj isKindOfClass:NSString.class]) {
        return ZZExtractVersionFromText((NSString *)obj);
    }

    if ([obj isKindOfClass:NSNumber.class]) return @"";

    if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) {
            NSString *v = ZZFindVersionDeep(child, depth + 1);
            if (v.length) return v;
        }
        return @"";
    }

    if (![obj isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = (NSDictionary *)obj;

    id canonical = d[@"zzSystemVersion"];
    if ([canonical isKindOfClass:NSString.class]) {
        NSString *v = ZZNormalizeVersion(canonical);
        if (v.length) return v;
    }

    NSArray *priorityKeys = @[
        @"iosVersion", @"iOSVersion", @"ios_version", @"systemVersion", @"system_version",
        @"systemVersionName", @"system_version_name", @"iphoneOSVersion", @"iphoneOsVersion",
        @"osVersion", @"os_version", @"ios", @"system"
    ];
    for (NSString *key in priorityKeys) {
        id value = d[key];
        if ([value isKindOfClass:NSString.class]) {
            NSString *v = ZZNormalizeVersion(value);
            if (v.length) return v;
            v = ZZExtractVersionFromText(value);
            if (v.length) return v;
        } else if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
            NSString *v = ZZFindVersionDeep(value, depth + 1);
            if (v.length) return v;
        }
    }

    id label = d[@"key"] ?: d[@"name"] ?: d[@"attrName"] ?: d[@"attributeName"] ?: d[@"title"] ?: d[@"label"];
    id value = d[@"value"] ?: d[@"attrValue"] ?: d[@"attributeValue"] ?: d[@"content"] ?: d[@"displayValue"];
    if ([label isKindOfClass:NSString.class] && ZZLooksLikeSystemVersionLabel(label)) {
        if ([value isKindOfClass:NSString.class]) {
            NSString *v = ZZNormalizeVersion(value);
            if (v.length) return v;
            v = ZZExtractVersionFromText(value);
            if (v.length) return v;
        } else if ([value isKindOfClass:NSNumber.class]) {
            NSString *v = ZZNormalizeVersion([value stringValue]);
            if (v.length) return v;
        } else if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
            NSString *v = ZZFindVersionDeep(value, depth + 1);
            if (v.length) return v;
        }
    }

    // Attribute records can use `params`, `attributes`, `attrs`, `infos`, etc.
    // Recurse into these before generic dictionary values.
    NSArray *preferredBranches = @[@"params", @"attributes", @"attrs", @"attributeList", @"attrList", @"itemId2AttrInfo", @"detail", @"detailInfo", @"detailData", @"respData", @"report", @"data", @"result"];
    for (NSString *key in preferredBranches) {
        id child = d[key];
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class] || [child isKindOfClass:NSString.class]) {
            NSString *v = ZZFindVersionDeep(child, depth + 1);
            if (v.length) return v;
        }
    }

    // Any value/content/display field containing an explicit iOS marker is safe.
    for (NSString *key in @[@"value", @"attrValue", @"attributeValue", @"content", @"text", @"displayValue", @"detailText", @"rawText", @"responseText", @"bodyText"]) {
        id candidate = d[key];
        if ([candidate isKindOfClass:NSString.class]) {
            NSString *v = ZZExtractVersionFromText(candidate);
            if (v.length) return v;
        }
    }

    // Contextual keys may contain a flattened label/value string.
    for (NSString *key in d) {
        id candidate = d[key];
        if (![candidate isKindOfClass:NSString.class]) continue;
        NSString *lowerKey = key.lowercaseString;
        BOOL contextual = ZZLooksLikeSystemVersionLabel(key) ||
                           [lowerKey containsString:@"version"] ||
                           [lowerKey containsString:@"os"] ||
                           [lowerKey containsString:@"detail"] ||
                           [lowerKey containsString:@"attr"];
        if (!contextual) continue;
        NSString *v = ZZExtractVersionFromText(candidate);
        if (v.length) return v;
    }

    // Generic version/modelVersion/etc. only count if the value itself clearly
    // identifies iOS. This preserves the v15 regression guard for 1.0.0.
    for (NSString *key in @[@"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"appVersion"]) {
        id candidate = d[key];
        if ([candidate isKindOfClass:NSString.class] && ZZStringContainsIOSMarker(candidate)) {
            NSString *v = ZZExtractVersionFromText(candidate);
            if (!v.length) v = ZZNormalizeVersion(candidate);
            if (v.length) return v;
        }
    }

    // Last pass over nested containers. This is bounded by depth to avoid the
    // expensive global runtime scan that caused the v11 watchdog issue.
    for (NSString *key in d) {
        id child = d[key];
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) {
            NSString *v = ZZFindVersionDeep(child, depth + 1);
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
    if (!version.length) return NO;
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
