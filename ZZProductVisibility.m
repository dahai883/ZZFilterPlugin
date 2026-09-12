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
        _entriesByID[pid] = entry;
        NSString *version = nil;
        for (NSString *key in @[@"version", @"modelVersion", @"goodsVersion", @"waresVersion", @"iosVersion", @"systemVersion", @"ios"]) {
            id value = entry[key];
            if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) { version = value; break; }
            if ([value respondsToSelector:@selector(stringValue)]) {
                NSString *s = [value stringValue];
                if (s.length) { version = s; break; }
            }
        }
        if (version.length) [versionList addObject:version];
    }
    self.versions = versionList.copy;
    NSLog(@"[ZZFilterUI] visibility cache updated entries=%lu ids=%lu versions=%lu",
          (unsigned long)entries.count, (unsigned long)ids.count, (unsigned long)versionList.count);
}

- (BOOL)shouldDisplayProductID:(NSString *)productID {
    if (!ZZSettings.shared.enabled || !productID.length) return YES;
    NSDictionary *entry = _entriesByID[productID];
    if (!entry) return YES;
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
    NSMutableDictionary *copy = [data mutableCopy];
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products"]) {
        id value = copy[key];
        if ([value isKindOfClass:NSArray.class]) {
            copy[key] = ZZFilteredModels(value);
            return copy;
        }
    }
    return data;
}
