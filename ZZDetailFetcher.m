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

static NSUInteger ZZDetailHTTPResponseCount;
static NSUInteger ZZDetailHTTP2xxCount;
static NSUInteger ZZDetailHTTPFailureCount;

NSUInteger ZZDetailHTTPResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTPResponseCount; } }
NSUInteger ZZDetailHTTP2xxResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTP2xxCount; } }
NSUInteger ZZDetailHTTPFailureResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTPFailureCount; } }

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
    // Preserve the entire source request query context. The endpoint can use
    // non-identifier parameters such as platform/source/token/quickStart that
    // are not present on the list item itself.
    ZZAppendQueryItemsFromURL(items, sourceRequest.URL, seenNames);

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
    // The reference uses a denylist rather than a narrow allowlist, which is
    // important for Zhuanzhuan's request-context headers that can vary by app
    // release. Never forward transport-managed or cookie headers verbatim.
    NSSet *deny = [NSSet setWithArray:@[
        @"host", @"content-length", @"connection", @"cookie",
        @"accept-encoding", @"proxy-connection", @"proxy-authenticate",
        @"proxy-authorization", @"te", @"trailer", @"transfer-encoding",
        @"upgrade"
    ]];
    [sourceHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSString *lower = key.lowercaseString;
        if (key.length && value.length && ![deny containsObject:lower]) {
            [request setValue:value forHTTPHeaderField:key];
        }
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

- (NSDictionary *)entryFromData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    if (error || !data.length || ![response isKindOfClass:NSHTTPURLResponse.class]) return nil;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode < 200 || http.statusCode > 299) return nil;

    // First give the deep object parser a chance to recover nested attributes.
    NSError *jsonError = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
    if (obj) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        NSString *version = ZZProductVersionFromObject(obj);
        if (version.length) entry[@"zzSystemVersion"] = version;

        if ([obj isKindOfClass:NSDictionary.class]) [entry addEntriesFromDictionary:(NSDictionary *)obj];
        if (!entry.count) entry = [NSMutableDictionary dictionaryWithDictionary:@{}];
        return version.length ? entry.copy : nil;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (!text.length) return nil;

    NSString *version = ZZProductVersionFromObject(text);
    if (!version.length) return nil;
    return @{ @"detailText": text, @"zzSystemVersion": version };
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
                    @synchronized (ZZDetailFetcher.class) {
                        ZZDetailHTTPResponseCount += 1;
                        if (http.statusCode >= 200 && http.statusCode <= 299) ZZDetailHTTP2xxCount += 1;
                        else ZZDetailHTTPFailureCount += 1;
                    }
                    NSString *contentType = http.allHeaderFields[@"Content-Type"] ?: http.allHeaderFields[@"content-type"] ?: @"";
                    ZZFilterDebugWrite(@"[ZZFilterDetail] response status=%ld type=%@ bytes=%lu url=%@",
                                       (long)http.statusCode, contentType,
                                       (unsigned long)data.length, request.URL.absoluteString ?: @"");
                }
                if (error) {
                    @synchronized (self) { if (!firstError) firstError = error; }
                } else {
                    NSDictionary *entry = [self entryFromData:data response:response error:error];
                    if (entry.count) {
                        NSMutableDictionary *candidate = [entry mutableCopy];
                        if (!ZZProductIDFromInfo(candidate).length) candidate[@"productId"] = pid;
                        NSString *version = ZZProductVersionFromDictionary(candidate);
                        if (version.length) {
                            candidate[@"zzSystemVersion"] = version;
                            @synchronized (entriesLock) { [entries addObject:candidate.copy]; }
                        }
                    } else if (data.length) {
                        // Keep a second text pass even when JSON parsed but the
                        // object shape was scalar or otherwise unexpected.
                        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
                        NSString *version = ZZProductVersionFromObject(text);
                        if (version.length) {
                            NSDictionary *candidate = @{ @"productId": pid, @"detailText": text, @"zzSystemVersion": version };
                            @synchronized (entriesLock) { [entries addObject:candidate]; }
                        }
                    }
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
        if (!text.length) return;
        NSString *directVersion = ZZProductVersionFromObject(text);
        if (directVersion.length && fallbackPID.length) {
            NSDictionary *candidate = @{ @"productId": fallbackPID, @"detailText": text, @"zzSystemVersion": directVersion };
            @synchronized (lock) { [entries addObject:candidate]; }
        }

        // Detail responses are often JSON encoded as a JSON string (sometimes
        // more than once). Try a few bounded decode layers, including percent
        // decoding, rather than requiring the text to start with '{' or '['.
        NSString *cursor = text;
        for (NSUInteger layer = 0; layer < 4; layer++) {
            NSData *data = [cursor dataUsingEncoding:NSUTF8StringEncoding];
            if (!data.length) break;
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
            if (!parsed || (parsed == obj)) break;
            if ([parsed isKindOfClass:NSString.class]) {
                NSString *next = [(NSString *)parsed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (!next.length || [next isEqualToString:cursor]) break;
                cursor = next;
                continue;
            }
            [self collectEntriesFromObject:parsed fallbackProductID:fallbackPID into:entries lock:lock];
            break;
        }
        NSString *decoded = [cursor stringByRemovingPercentEncoding];
        if (decoded.length && ![decoded isEqualToString:cursor]) {
            NSData *data = [decoded dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL] : nil;
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
                NSString *mappedPID = nil;
                if ([mapped isKindOfClass:NSDictionary.class]) mappedPID = ZZProductIDFromInfo(mapped);
                if (!mappedPID.length) mappedPID = mappedID.length ? mappedID : (pid.length ? pid : fallbackPID);
                [self collectEntriesFromObject:mapped fallbackProductID:mappedPID into:entries lock:lock];
            }
        }

        // Build an inherited parent record for attribute pairs so {key,value}
        // fields can still be associated with the product ID and title/link.
        id key = d[@"key"] ?: d[@"name"] ?: d[@"attrName"] ?: d[@"attributeName"];
        id value = d[@"value"] ?: d[@"attrValue"] ?: d[@"attributeValue"] ?: d[@"content"];
        if (pid.length && [key isKindOfClass:NSString.class] && (value != nil)) {
            NSString *keyLower = [key lowercaseString];
            BOOL systemLabel = [keyLower containsString:@"ios"] || [keyLower containsString:@"系统版本"] ||
                                [keyLower containsString:@"systemversion"] || [keyLower containsString:@"system_version"] ||
                                [keyLower containsString:@"system version"] || [keyLower containsString:@"os版本"];
            if (systemLabel) {
                NSMutableDictionary *merged = [candidate mutableCopy];
                merged[@"key"] = key;
                merged[@"value"] = value;
                NSString *v = ZZProductVersionFromObject(merged);
                if (v.length) {
                    merged[@"zzSystemVersion"] = v;
                    @synchronized (lock) { [entries addObject:merged.copy]; }
                }
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
