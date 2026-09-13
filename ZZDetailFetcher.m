#import "ZZDetailFetcher.h"
#import "ZZProductVisibility.h"
#import "ZZProductFilter.h"
#import "ZZDebug.h"
#import "ZZNetworkInterception.h"

@interface ZZDetailFetcher ()
- (void)collectEntriesFromObject:(id)obj fallbackProductID:(NSString * _Nullable)fallbackPID into:(NSMutableArray<NSDictionary *> *)entries lock:(NSObject *)lock;
@end

@implementation ZZDetailFetcher

+ (instancetype)shared {
    static ZZDetailFetcher *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.protocolClasses = @[];
        cfg.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        cfg.HTTPShouldSetCookies = YES;
        cfg.timeoutIntervalForRequest = 3.5;
        cfg.timeoutIntervalForResource = 5.0;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        ZZRegisterCookieStorage(cfg.HTTPCookieStorage);
    }
    return self;
}

static NSString *ZZQueryValue(NSURL *url, NSArray<NSString *> *names) {
    if (!url) return @"";
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[]) {
        for (NSString *name in names) {
            if ([item.name caseInsensitiveCompare:name] == NSOrderedSame && item.value.length) return item.value;
        }
    }
    return @"";
}

static void ZZAppendQueryItemsFromURL(NSMutableArray<NSURLQueryItem *> *items, NSURL *url, NSMutableSet<NSString *> *names) {
    if (!url) return;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[]) {
        if (!item.name.length || !item.value.length) continue;
        NSString *lower = item.name.lowercaseString;
        if ([names containsObject:lower]) continue;
        [names addObject:lower];
        [items addObject:[NSURLQueryItem queryItemWithName:item.name value:item.value]];
    }
}

- (NSURLRequest *)detailRequestForProductID:(NSString *)pid
                                    jumpURL:(NSURL *)jumpURL
                              sourceRequest:(NSURLRequest *)sourceRequest {
    if (!pid.length) return nil;

    // The reference starts from the real jump URL when available, then
    // augments it with source query items. For ordinary item/redirect URLs we
    // still call the canonical moreInfo endpoint while preserving those
    // identifiers instead of discarding the jumpURL query.
    NSURL *targetURL = nil;
    NSString *jumpScheme = jumpURL.scheme.lowercaseString ?: @"";
    NSString *jumpHost = jumpURL.host.lowercaseString ?: @"";
    NSString *jumpPath = jumpURL.path.lowercaseString ?: @"";
    BOOL jumpIsHTTP = [jumpScheme isEqualToString:@"http"] || [jumpScheme isEqualToString:@"https"];
    BOOL sameHost = [jumpHost hasSuffix:@"zhuanzhuan.com"] || [jumpHost hasSuffix:@"zhuanzhuan.com.cn"];
    BOOL looksLikeDetail = [jumpPath containsString:@"moreinfo"] || [jumpPath containsString:@"waresshow"];
    if (jumpURL && jumpIsHTTP && sameHost && looksLikeDetail) targetURL = jumpURL;

    NSURLComponents *components = targetURL
        ? [NSURLComponents componentsWithURL:targetURL resolvingAgainstBaseURL:NO]
        : [NSURLComponents componentsWithString:@"https://app.zhuanzhuan.com/zzopen/waresshow/moreInfo"];
    if (!components) return nil;

    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    ZZAppendQueryItemsFromURL(items, targetURL, seenNames);
    ZZAppendQueryItemsFromURL(items, jumpURL, seenNames);

    // Ensure the identifiers the reference explicitly propagates exist.
    NSArray<NSArray<NSString *> *> *pairs = @[
        @[@"productId", @"productId", @"goodsId", @"itemId", @"id"],
        @[@"infoId", @"infoId", @"strInfoId", @"infoid"],
        @[@"strInfoId", @"strInfoId", @"infoId", @"infoid"],
        @[@"uid", @"uid"],
        @[@"requestType", @"requestType"],
        @[@"packageId", @"packageId"],
        @[@"orderId", @"orderId"],
        @[@"storeQrCode", @"storeQrCode"],
        @[@"searchFrom", @"searchFrom"]
    ];
    for (NSArray *pair in pairs) {
        NSString *outName = pair.firstObject;
        if ([seenNames containsObject:outName.lowercaseString]) continue;
        NSArray *candidates = [pair subarrayWithRange:NSMakeRange(1, pair.count - 1)];
        NSString *value = ZZQueryValue(jumpURL, candidates);
        if (!value.length) value = ZZQueryValue(sourceRequest.URL, candidates);
        if (!value.length && [outName isEqualToString:@"productId"]) value = pid;
        if (value.length) {
            [seenNames addObject:outName.lowercaseString];
            [items addObject:[NSURLQueryItem queryItemWithName:outName value:value]];
        }
    }
    components.queryItems = items;
    targetURL = components.URL;
    if (!targetURL) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:targetURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 3.5;

    NSDictionary *sourceHeaders = sourceRequest.allHTTPHeaderFields ?: @{};
    NSSet *allowed = [NSSet setWithArray:@[
        @"Accept", @"Accept-Language", @"Authorization", @"Cookie", @"User-Agent",
        @"Referer", @"Origin", @"X-Requested-With", @"Content-Type", @"Cache-Control",
        @"Pragma", @"zzreqsign", @"zzreqt", @"zzreqallparam", @"zzreqversion",
        @"X-Api-Version", @"X-Device-Id", @"X-Requested-With"
    ]];
    [sourceHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSString *lower = key.lowercaseString;
        BOOL allowedName = [allowed containsObject:key] ||
                           [@["accept", "authorization", "cookie", "user-agent", "referer", "origin",
                              "zzreqsign", "zzreqt", "zzreqallparam", "zzreqversion", "x-requested-with",
                              "x-device-id", "x-api-version"] containsObject:lower];
        if (allowedName && key.length && value.length) [request setValue:value forHTTPHeaderField:key];
        (void)stop;
    }];

    NSArray<NSHTTPCookie *> *cookies = ZZCookiesForURL(targetURL);
    if (cookies.count) {
        NSDictionary *cookieFields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        NSString *cookie = cookieFields[@"Cookie"];
        if (cookie.length) [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    }
    if (![request valueForHTTPHeaderField:@"Accept"]) [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    if (![request valueForHTTPHeaderField:@"Referer"] && sourceRequest.URL.absoluteString.length) [request setValue:sourceRequest.URL.absoluteString forHTTPHeaderField:@"Referer"];
    return request;
}

- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
                         baseURL:(NSURL *)baseURL
                       headers:(NSDictionary<NSString *,NSString *> *)headers
                    completion:(ZZDetailCompletion)completion {
    [self fetchDetailsForProductIDs:productIDs jumpURLsByProductID:@{} sourceRequest:nil baseURL:baseURL headers:headers completion:completion];
}

- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
            jumpURLsByProductID:(NSDictionary<NSString *,NSURL *> *)jumpURLs
                  sourceRequest:(NSURLRequest *)sourceRequest
                        baseURL:(NSURL *)baseURL
                         headers:(NSDictionary<NSString *,NSString *> *)headers
                      completion:(ZZDetailCompletion)completion {
    if (!completion) return;
    if (productIDs.count == 0) { completion(@[], nil); return; }

    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    // Keep the bounded batch for stability, but larger than the old first page
    // and leave later pages to the list/UI flow.
    for (NSString *pid in productIDs) {
        if (![pid isKindOfClass:NSString.class] || !pid.length || [seen containsObject:pid]) continue;
        [seen addObject:pid];
        [ids addObject:pid];
        if (ids.count >= 24) break;
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSObject *entriesLock = [NSObject new];
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t slots = dispatch_semaphore_create(3);
    __block NSError *firstError = nil;

    for (NSString *pid in ids) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
            NSURL *jumpURL = jumpURLs[pid];
            NSMutableURLRequest *request = [self detailRequestForProductID:pid jumpURL:jumpURL sourceRequest:sourceRequest];
            if (!request && baseURL) {
                request = [NSMutableURLRequest requestWithURL:baseURL];
                request.HTTPMethod = @"GET";
            }
            [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
                if (key.length && value.length && ![request valueForHTTPHeaderField:key]) [request setValue:value forHTTPHeaderField:key];
                (void)stop;
            }];
            if (request && ![request valueForHTTPHeaderField:@"Cookie"]) {
                NSArray *cookies = ZZCookiesForURL(request.URL);
                NSString *cookie = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies][@"Cookie"];
                if (cookie.length) [request setValue:cookie forHTTPHeaderField:@"Cookie"];
            }
            if (!request) {
                dispatch_semaphore_signal(slots);
                dispatch_group_leave(group);
                return;
            }

            NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                    ZZStoreResponseCookies(http, response.URL ?: request.URL);
                    ZZFilterDebugWrite(@"[ZZFilterDetail] response status=%ld type=%@ bytes=%lu url=%@",
                                       (long)http.statusCode, http.allHeaderFields[@"Content-Type"] ?: @"",
                                       (unsigned long)data.length, request.URL.absoluteString ?: @"");
                }
                if (error) {
                    @synchronized (self) { if (!firstError) firstError = error; }
                } else if (data.length) {
                    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
                    [self collectEntriesFromObject:obj fallbackProductID:pid into:entries lock:entriesLock];
                }
                dispatch_semaphore_signal(slots);
                dispatch_group_leave(group);
            }];
            [task resume];
        });
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        ZZFilterDebugWrite(@"[ZZFilterDetail] complete requested=%lu resolved=%lu error=%@",
                           (unsigned long)ids.count, (unsigned long)entries.count,
                           firstError.localizedDescription ?: @"none");
        completion(entries.copy, firstError);
    });
}

- (void)collectEntriesFromObject:(id)obj fallbackProductID:(NSString *)fallbackPID into:(NSMutableArray<NSDictionary *> *)entries lock:(NSObject *)lock {
    if (!obj) return;
    if ([obj isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:NULL];
            if (parsed) [self collectEntriesFromObject:parsed fallbackProductID:fallbackPID into:entries lock:lock];
        }
        return;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)obj;
        NSMutableDictionary *candidate = [d mutableCopy];
        NSString *pid = ZZProductIDFromInfo(candidate);
        if (!pid.length) pid = fallbackPID;
        NSString *version = ZZProductVersionFromDictionary(candidate);
        if (version.length && pid.length) {
            candidate[@"productId"] = pid;
            @synchronized (lock) { [entries addObject:candidate.copy]; }
        }

        id respData = d[@"respData"];
        if ([respData isKindOfClass:NSDictionary.class] || [respData isKindOfClass:NSArray.class] || [respData isKindOfClass:NSString.class]) {
            [self collectEntriesFromObject:respData fallbackProductID:pid.length ? pid : fallbackPID into:entries lock:lock];
        }

        id report = d[@"report"];
        if ([report isKindOfClass:NSDictionary.class] || [report isKindOfClass:NSArray.class] || [report isKindOfClass:NSString.class]) {
            [self collectEntriesFromObject:report fallbackProductID:pid.length ? pid : fallbackPID into:entries lock:lock];
        }

        id attrMap = d[@"itemId2AttrInfo"];
        if ([attrMap isKindOfClass:NSDictionary.class]) {
            for (NSString *mappedID in (NSDictionary *)attrMap) {
                id mapped = ((NSDictionary *)attrMap)[mappedID];
                if (![mapped isKindOfClass:NSDictionary.class]) continue;
                NSMutableDictionary *entry = [mapped mutableCopy];
                NSString *mappedPID = ZZProductIDFromInfo(entry);
                if (!mappedPID.length) mappedPID = mappedID.length ? mappedID : (pid.length ? pid : fallbackPID);
                if (mappedPID.length) entry[@"productId"] = mappedPID;
                if (ZZProductVersionFromDictionary(entry).length && mappedPID.length) {
                    @synchronized (lock) { [entries addObject:entry.copy]; }
                }
                [self collectEntriesFromObject:entry fallbackProductID:mappedPID into:entries lock:lock];
            }
        }

        // Build an inherited parent record for attribute pairs so {key,value}
        // fields can still be associated with the product ID and title/link.
        id key = d[@"key"] ?: d[@"name"] ?: d[@"attrName"] ?: d[@"attributeName"];
        id value = d[@"value"] ?: d[@"attrValue"] ?: d[@"attributeValue"] ?: d[@"content"];
        if (pid.length && [key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) {
            NSString *keyLower = [key lowercaseString];
            BOOL systemLabel = [keyLower containsString:@"ios"] || [keyLower containsString:@"系统版本"] || [keyLower containsString:@"systemversion"] || [keyLower containsString:@"system_version"];
            if (systemLabel && [[value lowercaseString] containsString:@"ios"]) {
                NSMutableDictionary *merged = [candidate mutableCopy];
                merged[@"key"] = key;
                merged[@"value"] = value;
                @synchronized (lock) { [entries addObject:merged.copy]; }
            }
        }

        for (NSString *childKey in d) {
            if ([childKey isEqualToString:@"respData"] || [childKey isEqualToString:@"report"] || [childKey isEqualToString:@"itemId2AttrInfo"]) continue;
            id child = d[childKey];
            if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class] || [child isKindOfClass:NSString.class]) {
                [self collectEntriesFromObject:child fallbackProductID:pid.length ? pid : fallbackPID into:entries lock:lock];
            }
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)obj) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSString.class]) {
                [self collectEntriesFromObject:value fallbackProductID:fallbackPID into:entries lock:lock];
            }
        }
    }
}

- (void)collectEntriesFromObject:(id)obj into:(NSMutableArray *)entries {
    [self collectEntriesFromObject:obj fallbackProductID:nil into:entries lock:entries];
}

@end
