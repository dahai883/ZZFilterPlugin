#import "ZZDetailFetcher.h"
#import "ZZProductVisibility.h"
#import "ZZProductFilter.h"
#import "ZZDebug.h"
#import "ZZNetworkInterception.h"

@interface ZZDetailFetcher ()
- (void)collectEntriesFromObject:(id)obj fallbackProductID:(NSString * _Nullable)fallbackPID into:(NSMutableArray<NSDictionary *> *)entries lock:(NSObject *)lock;
@end

static NSString *ZZFormEscape(NSString *value) {
    if (!value.length) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._* "];
    NSString *v = [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    return [v stringByReplacingOccurrencesOfString:@" " withString:@"+"];
}

static NSData *ZZFormBodyFromURL(NSURL *url) {
    NSArray *items = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        if (!item.name.length) continue;
        [parts addObject:[NSString stringWithFormat:@"%@=%@", ZZFormEscape(item.name), ZZFormEscape(item.value ?: @"")]];
    }
    return parts.count ? [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding] : nil;
}

static NSData *ZZJSONBodyFromURL(NSURL *url) {
    NSArray *items = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in items) if (item.name.length) dict[item.name] = item.value ?: @"";
    return dict.count ? [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL] : nil;
}

static NSMutableURLRequest *ZZMakeVariant(NSURLRequest *base, NSString *method, NSData *body, NSString *contentType) {
    NSMutableURLRequest *r = [base mutableCopy];
    [r setValue:@"1" forHTTPHeaderField:@"X-ZZFilter-Internal-Detail"];
    r.HTTPMethod = method;
    r.HTTPBody = body;
    if (contentType.length) [r setValue:contentType forHTTPHeaderField:@"Content-Type"];
    return r;
}

static NSURL *ZZAlternateDetailURL(NSURL *url, NSUInteger index) {
    if (!url || index > 2) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!c) return nil;
    if (index == 0) return url;
    if (index == 1) c.path = @"/zzopen/waresshow/moreinfo";
    else c.path = @"/waresshow/moreinfo";
    return c.URL;
}


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
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.protocolClasses = @[];
        cfg.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        cfg.HTTPShouldSetCookies = YES;
        cfg.timeoutIntervalForRequest = 4.5;
        cfg.timeoutIntervalForResource = 5.0;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        ZZRegisterCookieStorage(cfg.HTTPCookieStorage);
    }
    return self;
}

static NSUInteger ZZDetailHTTPResponseCount;
static NSUInteger ZZDetailHTTP2xxCount;
static NSUInteger ZZDetailHTTPFailureCount;
static NSUInteger ZZDetailGETCount;
static NSUInteger ZZDetailPOSTFormCount;
static NSUInteger ZZDetailPOSTJSONCount;
static NSInteger ZZDetailLastStatusCode;

NSUInteger ZZDetailHTTPResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTPResponseCount; } }
NSUInteger ZZDetailHTTP2xxResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTP2xxCount; } }
NSUInteger ZZDetailHTTPFailureResponses(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailHTTPFailureCount; } }
NSInteger ZZDetailLastHTTPStatus(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailLastStatusCode; } }
NSUInteger ZZDetailGETRequests(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailGETCount; } }
NSUInteger ZZDetailPOSTFormRequests(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailPOSTFormCount; } }
NSUInteger ZZDetailPOSTJSONRequests(void) { @synchronized (ZZDetailFetcher.class) { return ZZDetailPOSTJSONCount; } }

static NSString *ZZQueryValue(NSURL *url, NSArray<NSString *> *names) {
    if (!url) return @"";
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[]) {
        for (NSString *name in names) {
            if ([item.name caseInsensitiveCompare:name] == NSOrderedSame && item.value.length) return item.value;
        }
    }
    return @"";
}

static NSDictionary<NSString *, NSString *> *ZZStringParamsFromData(NSData *data) {
    if (!data.length) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id key in (NSDictionary *)obj) {
            id value = ((NSDictionary *)obj)[key];
            if ([key isKindOfClass:NSString.class] && [value respondsToSelector:@selector(stringValue)]) {
                NSString *sv = [value isKindOfClass:NSString.class] ? value : [value stringValue];
                if (sv.length) out[key] = sv;
            }
        }
        return out.copy;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) return @{};
    NSURLComponents *components = [NSURLComponents componentsWithString:[@"https://zz.local/?" stringByAppendingString:text]];
    if (!components.queryItems.count) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name.length && item.value.length) out[item.name] = item.value;
    }
    return out.copy;
}

static NSArray<NSString *> *ZZReferenceDetailQueryNames(void) {
    // Keep the detail request's query shape aligned with the app's normal
    // detail-request context: productId plus the small set of source-context
    // fields observed on the reference path. Do not forward list-only query
    // parameters wholesale.
    return @[
        @"uid", @"previewToken", @"infoId", @"strInfoId", @"infoid",
        @"platform", @"requestType", @"packageId", @"t", @"ip", @"token",
        @"orderId", @"doubleTrackFineness", @"source", @"storeQrCode",
        @"searchFrom", @"quickStart"
    ];
}

static void ZZAppendReferenceQueryItems(NSMutableArray<NSURLQueryItem *> *items,
                                         NSMutableSet<NSString *> *seen,
                                         NSURL *url) {
    if (!url) return;
    NSSet<NSString *> *allowed = [NSSet setWithArray:ZZReferenceDetailQueryNames()];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems ?: @[]) {
        if (!item.name.length || !item.value.length) continue;
        NSString *lower = item.name.lowercaseString;
        if ([lower isEqualToString:@"productid"] || ![allowed containsObject:item.name]) continue;
        if ([seen containsObject:lower]) continue;
        [seen addObject:lower];
        [items addObject:[NSURLQueryItem queryItemWithName:item.name value:item.value]];
    }
}

static void ZZAppendReferenceQueryItemsFromDictionary(NSMutableArray<NSURLQueryItem *> *items,
                                                       NSMutableSet<NSString *> *seen,
                                                       NSDictionary<NSString *,NSString *> *params) {
    if (!params.count) return;
    NSSet<NSString *> *allowed = [NSSet setWithArray:ZZReferenceDetailQueryNames()];
    for (NSString *name in params) {
        NSString *value = params[name];
        if (!name.length || !value.length) continue;
        NSString *lower = name.lowercaseString;
        if ([lower isEqualToString:@"productid"] || ![allowed containsObject:name]) continue;
        if ([seen containsObject:lower]) continue;
        [seen addObject:lower];
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }
}

static NSDictionary<NSString *,NSString *> *ZZSourceRequestParams(NSURLRequest *sourceRequest) {
    if (!sourceRequest) return @{};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSURLComponents *uc = [NSURLComponents componentsWithURL:sourceRequest.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in uc.queryItems ?: @[]) {
        if (item.name.length && item.value.length) params[item.name] = item.value;
    }
    NSString *contentType = [sourceRequest valueForHTTPHeaderField:@"Content-Type"].lowercaseString ?: @"";
    if (sourceRequest.HTTPBody.length) {
        NSDictionary *body = ZZStringParamsFromData(sourceRequest.HTTPBody);
        [body enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { params[key] = value; (void)stop; }];
    }
    // zzreqallparam is an app-level request-context header seen on the normal
    // search traffic. It is commonly URL-encoded JSON/form data; use it only
    // as an additional source of the small reference query field set.
    NSString *allParam = [sourceRequest valueForHTTPHeaderField:@"zzreqallparam"];
    if (allParam.length) {
        NSString *decoded = [allParam stringByRemovingPercentEncoding] ?: allParam;
        NSData *d = [decoded dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *headerParams = ZZStringParamsFromData(d);
        [headerParams enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { params[key] = value; (void)stop; }];
        NSURLComponents *hc = [NSURLComponents componentsWithString:[@"https://zz.local/?" stringByAppendingString:decoded]];
        for (NSURLQueryItem *item in hc.queryItems ?: @[]) if (item.name.length && item.value.length) params[item.name] = item.value;
    }
    (void)contentType;
    return params.copy;
}


- (NSURLRequest *)detailRequestForProductID:(NSString *)pid
                                    jumpURL:(NSURL *)jumpURL
                              sourceRequest:(NSURLRequest *)sourceRequest {
    if (!pid.length) return nil;

    NSURL *targetURL = nil;
    NSString *jumpScheme = jumpURL.scheme.lowercaseString ?: @"";
    NSString *jumpHost = jumpURL.host.lowercaseString ?: @"";
    NSString *jumpPath = jumpURL.path.lowercaseString ?: @"";
    BOOL jumpIsHTTP = [jumpScheme isEqualToString:@"http"] || [jumpScheme isEqualToString:@"https"];
    BOOL sameHost = [jumpHost hasSuffix:@"zhuanzhuan.com"] || [jumpHost hasSuffix:@"zhuanzhuan.com.cn"];
    BOOL looksLikeDetail = [jumpPath containsString:@"/waresshow/moreinfo"] || [jumpPath containsString:@"moreinfo"] ||
                           [jumpPath containsString:@"detail"] || [jumpPath containsString:@"item"] ||
                           [jumpPath containsString:@"goods"] || [jumpPath containsString:@"product"];
    // v36: if the list gives us a same-host HTTP(S) jump URL, prefer it even
    // when its path is opaque. The app can use short/deep-link paths that do
    // not contain the word "detail" while still carrying the required context.
    if (jumpURL && jumpIsHTTP && sameHost) targetURL = jumpURL;

    NSURLComponents *components = targetURL
        ? [NSURLComponents componentsWithURL:targetURL resolvingAgainstBaseURL:NO]
        : [NSURLComponents componentsWithString:@"https://app.zhuanzhuan.com/zzopen/waresshow/moreInfo"];
    if (!components) return nil;

    // If the listing supplied a real HTTP(S) jump/detail URL, preserve its
    // complete query string first. Those links can carry opaque context or
    // server-generated parameters that must not be reconstructed or dropped.
    // Only add productId/context values that are genuinely missing.
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seenQueryNames = [NSMutableSet set];
    if (targetURL) {
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:targetURL resolvingAgainstBaseURL:NO].queryItems ?: @[]) {
            if (!item.name.length) continue;
            NSString *lower = item.name.lowercaseString;
            if ([lower isEqualToString:@"productid"]) {
                if (item.value.length) { [seenQueryNames addObject:lower]; [items addObject:item]; }
                continue;
            }
            if (![seenQueryNames containsObject:lower]) {
                [seenQueryNames addObject:lower];
                [items addObject:item];
            }
        }
    }
    if (![seenQueryNames containsObject:@"productid"]) {
        [items insertObject:[NSURLQueryItem queryItemWithName:@"productId" value:pid] atIndex:0];
        [seenQueryNames addObject:@"productid"];
    }
    // v37: the search request can be POST-based. In that case uid/infoId/etc.
    // may live in HTTPBody or zzreqallparam instead of URL.query. Carry only
    // the reference detail-context keys forward.
    ZZAppendReferenceQueryItems(items, seenQueryNames, sourceRequest.URL);
    ZZAppendReferenceQueryItemsFromDictionary(items, seenQueryNames, ZZSourceRequestParams(sourceRequest));
    components.queryItems = items;
    NSURL *finalURL = components.URL;
    if (!finalURL) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:finalURL];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 5.0;
    // v56: requests created by the plugin itself must never be counted as
    // "real app traffic" by the passive observer. This separates our
    // diagnostic probes from the app's own detail requests.
    [request setValue:@"1" forHTTPHeaderField:@"X-ZZFilter-Internal-Detail"];

    NSDictionary *sourceHeaders = sourceRequest.allHTTPHeaderFields ?: @{};
    // Preserve application-level headers from the real app request, including
    // its normal auth/context fields. Only strip hop-by-hop/transport-managed
    // headers that URLSession should generate itself.
    NSSet *deny = [NSSet setWithArray:@[
        @"host", @"content-length", @"cookie", @"accept-encoding", @"connection",
        @"proxy-connection", @"proxy-authenticate", @"proxy-authorization",
        @"te", @"trailer", @"transfer-encoding", @"upgrade"
    ]];
    [sourceHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (key.length && value.length && ![deny containsObject:key.lowercaseString]) {
            [request setValue:value forHTTPHeaderField:key];
        }
        (void)stop;
    }];

    NSArray<NSHTTPCookie *> *cookies = ZZCookiesForURL(finalURL);
    if (cookies.count) {
        NSString *cookie = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies][@"Cookie"];
        if (cookie.length) [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    }
    if (![request valueForHTTPHeaderField:@"Accept"])
        [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];

    // If the supplied jump URL is a normal HTTP(S) detail URL, use it as the
    // referer; otherwise preserve an existing source-request Referer.
    if (jumpURL && jumpIsHTTP && sameHost && looksLikeDetail) {
        [request setValue:jumpURL.absoluteString forHTTPHeaderField:@"Referer"];
    } else {
        NSString *sourceReferer = [sourceRequest valueForHTTPHeaderField:@"Referer"];
        if (sourceReferer.length) [request setValue:sourceReferer forHTTPHeaderField:@"Referer"];
    }
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
        if (ids.count >= 12) break;
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

            // v35: the detail endpoint is rejecting the current GET with 405.
            // Treat 400/405 as a request-shape mismatch and try bounded POST
            // encodings before giving up. 405 specifically means the resource
            // does not allow the method used for that request.

            __block NSData *bestData = nil;
            __block NSURLResponse *bestResponse = nil;
            __block NSError *bestError = nil;

            void (^recordResponse)(NSURLRequest *, NSData *, NSURLResponse *, NSError *) = ^(NSURLRequest *req, NSData *data, NSURLResponse *response, NSError *error) {
                bestData = data;
                bestResponse = response;
                bestError = error;
                if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                    ZZStoreResponseCookies(http, response.URL ?: req.URL);
                    @synchronized (ZZDetailFetcher.class) {
                        ZZDetailHTTPResponseCount += 1;
                        ZZDetailLastStatusCode = http.statusCode;
                        if (http.statusCode >= 200 && http.statusCode <= 299) ZZDetailHTTP2xxCount += 1;
                        else ZZDetailHTTPFailureCount += 1;
                    }
                    NSString *ct = http.allHeaderFields[@"Content-Type"] ?: http.allHeaderFields[@"content-type"] ?: @"";
                    NSString *preview = @"";
                    if (data.length) {
                        NSString *t = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        if (!t.length) t = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
                        if (t.length > 160) t = [t substringToIndex:160];
                        preview = t ?: @"";
                    }
                    NSString *allow = http.allHeaderFields[@"Allow"] ?: http.allHeaderFields[@"allow"] ?: @"";
                    @synchronized (ZZDetailFetcher.class) {
                        if ([req.HTTPMethod caseInsensitiveCompare:@"GET"] == NSOrderedSame) ZZDetailGETCount += 1;
                        else if ([req.HTTPMethod caseInsensitiveCompare:@"POST"] == NSOrderedSame) {
                            NSString *ctype = [req valueForHTTPHeaderField:@"Content-Type"] ?: @"";
                            if ([ctype.lowercaseString containsString:@"application/json"]) ZZDetailPOSTJSONCount += 1;
                            else ZZDetailPOSTFormCount += 1;
                        }
                    }
                    ZZFilterDebugWrite(@"[ZZFilterDetail] method=%@ status=%ld allow=%@ type=%@ bytes=%lu body=%@ url=%@",
                                       req.HTTPMethod ?: @"?", (long)http.statusCode, allow, ct,
                                       (unsigned long)data.length, preview, req.URL.absoluteString ?: @"");
                } else if (error) {
                    ZZFilterDebugWrite(@"[ZZFilterDetail] method=%@ transport-error domain=%@ code=%ld desc=%@ url=%@",
                                       req.HTTPMethod ?: @"?", error.domain ?: @"", (long)error.code,
                                       error.localizedDescription ?: @"", req.URL.absoluteString ?: @"");
                }
            };

            __block NSData *getData = nil;
            __block NSURLResponse *getResponse = nil;
            __block NSError *getError = nil;
            dispatch_semaphore_t waitGet = dispatch_semaphore_create(0);
            NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                getData = data; getResponse = response; getError = error;
                dispatch_semaphore_signal(waitGet);
            }];
            [task resume];
            dispatch_semaphore_wait(waitGet, DISPATCH_TIME_FOREVER);
            recordResponse(request, getData, getResponse, getError);

            NSInteger status = [getResponse isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)getResponse statusCode] : 0;
            BOOL resolved = NO;
            if (status >= 200 && status <= 299) {
                NSDictionary *entry = [self entryFromData:getData response:getResponse error:getError];
                if (entry.count) {
                    NSMutableDictionary *candidate = [entry mutableCopy];
                    if (!ZZProductIDFromInfo(candidate).length) candidate[@"productId"] = pid;
                    NSString *version = ZZProductVersionFromDictionary(candidate);
                    if (version.length) { candidate[@"zzSystemVersion"] = version; @synchronized (entriesLock) { [entries addObject:candidate.copy]; } resolved = YES; }
                }
                if (!resolved && getData.length) {
                    NSString *text = [[NSString alloc] initWithData:getData encoding:NSUTF8StringEncoding];
                    if (!text.length) text = [[NSString alloc] initWithData:getData encoding:NSASCIIStringEncoding];
                    NSString *version = ZZProductVersionFromObject(text);
                    if (version.length) { NSDictionary *candidate = @{@"productId":pid,@"detailText":text,@"zzSystemVersion":version}; @synchronized (entriesLock) { [entries addObject:candidate]; } resolved = YES; }
                }
            }

            // v56: do not generate speculative alternate-method requests here.
            // The previous versions turned one product into many synthetic 400/405
            // requests, which polluted the observer and obscured the app's real
            // detail traffic. The passive observer now captures the app's own
            // successful detail response instead.

            if (!resolved && bestError) { @synchronized (self) { if (!firstError) firstError = bestError; } }
            dispatch_semaphore_signal(slots);
            dispatch_group_leave(group);
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
