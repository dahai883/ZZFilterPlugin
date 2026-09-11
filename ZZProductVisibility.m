#import "ZZProductVisibility.h"
#import "ZZSettings.h"
#import "ZZProductFilter.h"

@implementation ZZProductVisibility {
    NSSet<NSString *> *_hiddenProductIDs;
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
        _hiddenProductIDs = [NSSet set];
        _versions = @[];
    }
    return self;
}

- (void)recordEntries:(NSArray *)entries forProductIDs:(NSArray<NSString *> *)productIDs {
    (void)entries;
    NSMutableSet *ids = [NSMutableSet set];
    for (NSString *pid in productIDs ?: @[]) {
        if (pid.length) [ids addObject:pid];
    }
    _hiddenProductIDs = [ids copy];
}

- (BOOL)shouldDisplayProductID:(NSString *)productID {
    if (!ZZSettings.shared.enabled) return YES;
    if (!productID.length) return YES;
    return ![_hiddenProductIDs containsObject:productID];
}

@end

NSString *ZZProductIDFromInfo(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class]) return @"";
    for (NSString *key in @[@"id", @"productId", @"goodsId", @"itemId", @"listingId", @"spuId"]) {
        id v = info[key];
        if ([v isKindOfClass:NSString.class] && [v length]) return v;
        if ([v respondsToSelector:@selector(stringValue)]) {
            NSString *s = [v stringValue];
            if (s.length) return s;
        }
    }
    return @"";
}

static NSDictionary *ZZModelDictionary(id model) {
    if ([model isKindOfClass:NSDictionary.class]) return model;
    if ([model respondsToSelector:@selector(dictionaryWithValuesForKeys:)]) {
        NSArray *keys = @[@"id", @"productId", @"goodsId", @"itemId", @"listingId",
                         @"title", @"name", @"price", @"sellPrice", @"salePrice",
                         @"currentPrice", @"amount", @"version", @"modelVersion"];
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
    for (id model in models) if (ZZShouldKeepModel(model)) [result addObject:model];
    NSLog(@"[ZZFilterUI] models before=%lu after=%lu", (unsigned long)models.count, (unsigned long)result.count);
    return result;
}

id ZZFilterRenderedData(id data) {
    if ([data isKindOfClass:NSArray.class]) return ZZFilteredModels(data);
    if (![data isKindOfClass:NSDictionary.class] || !ZZSettings.shared.enabled) return data;
    NSMutableDictionary *copy = [data mutableCopy];
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"goods", @"products"]) {
        id value = copy[key];
        if ([value isKindOfClass:NSArray.class]) {
            copy[key] = ZZFilteredModels(value);
            return copy;
        }
    }
    return data;
}
