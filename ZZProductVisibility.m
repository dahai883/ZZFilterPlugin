#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import "ZZProductFilter.h"

@implementation ZZProductVisibility {
    NSMutableDictionary<NSString *, NSDictionary *> *_entriesByID;
}

+ (instancetype)shared {
    static ZZProductVisibility *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [ZZProductVisibility new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entriesByID = [NSMutableDictionary dictionary];
        _versions = @[];
    }
    return self;
}

- (void)recordEntries:(NSArray *)entries forProductIDs:(NSArray<NSString *> *)productIDs {
    NSArray *ids = productIDs ?: @[];
    NSMutableArray *versionList = [NSMutableArray array];
    for (NSUInteger i = 0; i < entries.count; i++) {
        id entry = entries[i];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *pid = i < ids.count ? ids[i] : ZZProductIDFromInfo(entry);
        if (![pid isKindOfClass:NSString.class] || !pid.length) continue;
        @synchronized (self) {
            NSDictionary *old = _entriesByID[pid];
            if ([old isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary *merged = [old mutableCopy];
                [merged addEntriesFromDictionary:entry];
                _entriesByID[pid] = merged.copy;
            } else {
                _entriesByID[pid] = entry;
            }
        }
        NSString *version = ZZProductVersionFromDictionary(entry);
        if (version.length) [versionList addObject:version];
    }
    self.versions = versionList.copy;
    NSLog(@"[ZZFilterUI] visibility cache updated entries=%lu ids=%lu versions=%lu",
          (unsigned long)entries.count, (unsigned long)ids.count, (unsigned long)versionList.count);
}

- (NSUInteger)cachedEntryCount {
    @synchronized (self) { return _entriesByID.count; }
}

- (NSArray<NSDictionary *> *)cachedEntriesMatchingCurrentVersionRange {
    ZZSettings *s = ZZSettings.shared;
    ZZProductFilter *filter = [ZZProductFilter new];
    filter.enabled = s.enabled;
    filter.minimumVersion = s.minimumVersion;
    filter.maximumVersion = s.maximumVersion;
    NSMutableArray *result = [NSMutableArray array];
    @synchronized (self) {
        for (NSDictionary *entry in _entriesByID.allValues) {
            NSString *version = ZZProductVersionFromDictionary(entry);
            // A configured range means the result sheet must contain only
            // entries whose actual system version is known and in range.
            if ((s.minimumVersion.length || s.maximumVersion.length) && !version.length) continue;
            if ([filter shouldDisplayProduct:entry]) [result addObject:entry];
        }
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *va = ZZProductVersionFromDictionary(a);
        NSString *vb = ZZProductVersionFromDictionary(b);
        NSComparisonResult vr = [va compare:vb options:NSNumericSearch];
        if (vr != NSOrderedSame) return vr == NSOrderedAscending ? NSOrderedDescending : NSOrderedAscending;
        NSString *ta = a[@"title"] ?: a[@"name"] ?: @"";
        NSString *tb = b[@"title"] ?: b[@"name"] ?: @"";
        return [ta localizedCaseInsensitiveCompare:tb];
    }];
    return result.copy;
}

- (NSString *)cachedURLForProductID:(NSString *)productID {
    if (!productID.length) return @"";
    NSDictionary *entry = nil;
    @synchronized (self) { entry = _entriesByID[productID]; }
    if (![entry isKindOfClass:NSDictionary.class]) return @"";

    NSArray *keys = @[@"jumpUrl", @"jumpURL", @"jump_url", @"shareUrl", @"shareURL", @"share_url",
                     @"detailUrl", @"detailURL", @"detail_url", @"itemUrl", @"itemURL", @"item_url",
                     @"url", @"link", @"h5Url", @"h5URL", @"webUrl", @"webURL"];
    for (NSString *key in keys) {
        id v = entry[key];
        if ([v isKindOfClass:NSURL.class]) return ((NSURL *)v).absoluteString ?: @"";
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) {
            NSString *u = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if ([u hasPrefix:@"http://"] || [u hasPrefix:@"https://"] || [u hasPrefix:@"zz://"]) return u;
        }
    }

    // Some responses nest the navigational URL inside a jump/detail object.
    for (NSString *key in @[@"jump", @"detail", @"share", @"linkInfo", @"redirect"]) {
        id child = entry[key];
        if ([child isKindOfClass:NSDictionary.class]) {
            NSDictionary *d = (NSDictionary *)child;
            for (NSString *k in keys) {
                id v = d[k];
                if ([v isKindOfClass:NSURL.class]) return ((NSURL *)v).absoluteString ?: @"";
                if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) {
                    NSString *u = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if ([u hasPrefix:@"http://"] || [u hasPrefix:@"https://"] || [u hasPrefix:@"zz://"]) return u;
                }
            }
        }
    }
    return @"";
}

- (BOOL)shouldDisplayProductID:(NSString *)productID {
    if (!ZZSettings.shared.enabled || !productID.length) return YES;
    NSDictionary *entry = nil;
    @synchronized (self) { entry = _entriesByID[productID]; }
    if (!entry) return !(ZZSettings.shared.minimumVersion.length || ZZSettings.shared.maximumVersion.length);
    if ((ZZSettings.shared.minimumVersion.length || ZZSettings.shared.maximumVersion.length) && !ZZProductVersionFromDictionary(entry).length) return NO;
    ZZProductFilter *filter = [ZZProductFilter new];
    ZZSettings *s = ZZSettings.shared;
    filter.enabled = s.enabled;
    filter.minimumText = s.minimumText;
    filter.maximumText = s.maximumText;
    filter.minimumVersion = s.minimumVersion;
    filter.maximumVersion = s.maximumVersion;
    return [filter shouldDisplayProduct:entry];
}

@end

NSString *ZZProductIDFromInfo(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class]) return @"";
    for (NSString *key in @[@"id", @"productId", @"goodsId", @"itemId", @"listingId", @"spuId", @"strInfoId", @"infoid"]) {
        id v = info[key];
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
        if ([v respondsToSelector:@selector(stringValue)]) {
            NSString *s = [v stringValue];
            if (s.length) return s;
        }
    }
    return @"";
}

static NSUInteger ZZModelsProcessed;
static NSUInteger ZZModelsHidden;

NSUInteger ZZFilterModelsProcessedCount(void) { return ZZModelsProcessed; }
NSUInteger ZZFilterModelsHiddenCount(void) { return ZZModelsHidden; }
void ZZResetFilterDiagnostics(void) { ZZModelsProcessed = 0; ZZModelsHidden = 0; }

static NSDictionary *ZZModelDictionary(id model) {
    if ([model isKindOfClass:NSDictionary.class]) return model;
    if ([model respondsToSelector:@selector(dictionaryWithValuesForKeys:)]) {
        NSArray *keys = @[@"id", @"productId", @"goodsId", @"itemId", @"listingId", @"strInfoId", @"infoid",
                         @"title", @"name", @"price", @"sellPrice", @"salePrice", @"currentPrice", @"amount",
                         @"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"iosVersion", @"systemVersion"];
        @try { return [model dictionaryWithValuesForKeys:keys]; }
        @catch (__unused NSException *e) { return nil; }
    }
    return nil;
}

BOOL ZZShouldKeepModel(id model) {
    NSDictionary *d = ZZModelDictionary(model);
    if (!d) return YES;
    NSString *pid = ZZProductIDFromInfo(d);
    if (pid.length && ![[ZZProductVisibility shared] shouldDisplayProductID:pid]) return NO;
    ZZProductFilter *filter = [ZZProductFilter new];
    ZZSettings *s = ZZSettings.shared;
    filter.enabled = s.enabled;
    filter.minimumText = s.minimumText;
    filter.maximumText = s.maximumText;
    filter.minimumVersion = s.minimumVersion;
    filter.maximumVersion = s.maximumVersion;
    return [filter shouldDisplayProduct:d];
}

NSArray *ZZFilteredModels(NSArray *models) {
    if (![models isKindOfClass:NSArray.class] || !ZZSettings.shared.enabled) return models;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:models.count];
    NSUInteger hidden = 0;
    for (id model in models) {
        ZZModelsProcessed += 1;
        if (ZZShouldKeepModel(model)) [result addObject:model]; else { hidden++; ZZModelsHidden += 1; }
    }
    NSLog(@"[ZZFilterUI] models before=%lu after=%lu hidden=%lu",
          (unsigned long)models.count, (unsigned long)result.count, (unsigned long)hidden);
    return result;
}

id ZZFilterRenderedData(id data) {
    if ([data isKindOfClass:NSArray.class]) return ZZFilteredModels(data);
    if (![data isKindOfClass:NSDictionary.class] || !ZZSettings.shared.enabled) return data;
    NSMutableDictionary *copy = (NSMutableDictionary *)[data mutableCopy];
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products"]) {
        id value = copy[key];
        if ([value isKindOfClass:NSArray.class]) {
            NSArray *arrayValue = (NSArray *)value;
            NSArray *filtered = ZZFilteredModels(arrayValue);
            copy[key] = filtered;
            return copy;
        }
    }
    return data;
}
