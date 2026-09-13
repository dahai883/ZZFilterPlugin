#import "ZZFilterURLProtocol.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"
#import "ZZDebug.h"
#import "ZZProductVisibility.h"
#import "ZZDetailFetcher.h"
#import "ZZNetworkInterception.h"

static NSString * const kHandledKey = @"ZZFilterHandledRequest";
static NSUInteger ZZNetworkInterceptedCount;
static NSUInteger ZZNetworkModifiedCount;
static NSUInteger ZZDetailPrefetchCount;
static NSUInteger ZZDetailPrefetchEntryCount;

NSUInteger ZZNetworkInterceptedRequests(void) { return ZZNetworkInterceptedCount; }
NSUInteger ZZNetworkModifiedResponses(void) { return ZZNetworkModifiedCount; }
NSUInteger ZZDetailPrefetchRequests(void) { return ZZDetailPrefetchCount; }
NSUInteger ZZDetailPrefetchEntries(void) { return ZZDetailPrefetchEntryCount; }

@interface ZZFilterURLProtocol () <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *responseData;
@property(nonatomic, strong) NSURLResponse *receivedResponse;
@property(nonatomic, strong) NSURLRequest *sourceRequest;
@property(nonatomic) BOOL shouldProcessResponse;
@end

@implementation ZZFilterURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return NO;
    NSString *host = request.URL.host.lowercaseString ?: @"";
    NSString *path = request.URL.path.lowercaseString ?: @"";
    BOOL hostOK = [host hasSuffix:@"zhuanzhuan.com"] || [host hasSuffix:@"zhuanzhuan.com.cn"];
    if (!hostOK) return NO;
    return [path containsString:@"/zz/transfer/search"] ||
           [path containsString:@"transmitparamsearch"] ||
           [path containsString:@"waresshow/moreinfo"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

+ (void)installOnSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    if (!configuration) return;
    ZZRegisterCookieStorage(configuration.HTTPCookieStorage);
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    if (![classes containsObject:self]) [classes insertObject:self atIndex:0];
    configuration.protocolClasses = classes;
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

static NSString *ZZFallbackProductIDFromRequest(NSURLRequest *request) {
    NSString *pid = ZZQueryValue(request.URL, @[@"productId", @"productID", @"goodsId", @"itemId", @"infoId", @"strInfoId", @"infoid"]);
    return pid ?: @"";
}

static BOOL ZZLooksLikeProductDictionary(NSDictionary *d) {
    return d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"itemId"] || d[@"title"] || d[@"name"];
}

static NSArray *ZZFindProductArray(id root, NSString **pathOut) {
    if ([root isKindOfClass:NSArray.class]) {
        NSUInteger hits = 0;
        for (id item in (NSArray *)root) {
            if ([item isKindOfClass:NSDictionary.class] && ZZLooksLikeProductDictionary(item)) { hits++; break; }
        }
        if (hits) { if (pathOut) *pathOut = @"$"; return root; }
        return nil;
    }
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dict = root;
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products", @"data"]) {
        id value = dict[key];
        NSArray *found = ZZFindProductArray(value, NULL);
        if (found) {
            if (pathOut) *pathOut = [NSString stringWithFormat:@"$.%@", key];
            return found;
        }
    }
    for (NSString *key in dict) {
        id value = dict[key];
        if (![value isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSArray.class]) continue;
        NSArray *found = ZZFindProductArray(value, NULL);
        if (found) { if (pathOut) *pathOut = [NSString stringWithFormat:@"$.%@", key]; return found; }
    }
    return nil;
}

static void ZZCollectVersionEntries(id root, NSString *fallbackPID, NSUInteger depth, NSUInteger *countOut) {
    if (depth > 10 || !root) return;
    if ([root isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)root stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:NULL];
            if (parsed) ZZCollectVersionEntries(parsed, fallbackPID, depth + 1, countOut);
        }
        return;
    }
    if ([root isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = root;
        NSMutableDictionary *entry = [d mutableCopy];
        NSString *pid = ZZProductIDFromInfo(entry);
        if (!pid.length) pid = fallbackPID;
        NSString *version = ZZProductVersionFromDictionary(entry);
        if (pid.length && version.length) {
            entry[@"productId"] = pid;
            [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[pid]];
            if (countOut) *countOut += 1;
        }

        id attrMap = d[@"itemId2AttrInfo"];
        if ([attrMap isKindOfClass:NSDictionary.class]) {
            for (NSString *mappedID in (NSDictionary *)attrMap) {
                id mapped = ((NSDictionary *)attrMap)[mappedID];
                NSMutableDictionary *mappedEntry = nil;
                if ([mapped isKindOfClass:NSDictionary.class]) mappedEntry = [mapped mutableCopy];
                else if ([mapped isKindOfClass:NSArray.class]) {
                    for (id item in (NSArray *)mapped) {
                        if ([item isKindOfClass:NSDictionary.class]) {
                            NSMutableDictionary *child = [item mutableCopy];
                            if (!ZZProductIDFromInfo(child).length && mappedID.length) child[@"productId"] = mappedID;
                            ZZCollectVersionEntries(child, mappedID.length ? mappedID : pid, depth + 1, countOut);
                        }
                    }
                }
                if (mappedEntry) {
                    if (!ZZProductIDFromInfo(mappedEntry).length && mappedID.length) mappedEntry[@"productId"] = mappedID;
                    NSString *v = ZZProductVersionFromDictionary(mappedEntry);
                    if (v.length && mappedID.length) {
                        [[ZZProductVisibility shared] recordEntries:@[mappedEntry] forProductIDs:@[mappedID]];
                        if (countOut) *countOut += 1;
                    }
                    ZZCollectVersionEntries(mappedEntry, mappedID.length ? mappedID : pid, depth + 1, countOut);
                }
            }
        }

        id respData = d[@"respData"];
        if (respData) ZZCollectVersionEntries(respData, pid.length ? pid : fallbackPID, depth + 1, countOut);
        id report = d[@"report"];
        if (report) ZZCollectVersionEntries(report, pid.length ? pid : fallbackPID, depth + 1, countOut);

        for (NSString *key in d) {
            if ([key isEqualToString:@"itemId2AttrInfo"] || [key isEqualToString:@"respData"] || [key isEqualToString:@"report"]) continue;
            id value = d[key];
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSString.class]) {
                ZZCollectVersionEntries(value, pid.length ? pid : fallbackPID, depth + 1, countOut);
            }
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)root) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSString.class]) {
                ZZCollectVersionEntries(value, fallbackPID, depth + 1, countOut);
            }
        }
    }
}

static void ZZCollectProductIDs(id root, NSMutableArray<NSString *> *ids, NSUInteger depth) {
    if (depth > 8 || ids.count >= 24 || !root) return;
    if ([root isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)root stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            if (parsed) ZZCollectProductIDs(parsed, ids, depth + 1);
        }
        return;
    }
    if ([root isKindOfClass:NSDictionary.class]) {
        NSString *pid = ZZProductIDFromInfo(root);
        if (pid.length && ![ids containsObject:pid]) [ids addObject:pid];
        for (id value in ((NSDictionary *)root).allValues) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSString.class]) {
                ZZCollectProductIDs(value, ids, depth + 1);
                if (ids.count >= 24) return;
            }
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)root) {
            ZZCollectProductIDs(value, ids, depth + 1);
            if (ids.count >= 24) return;
        }
    }
}

static BOOL ZZReplaceFirstProductArray(id root, NSArray *filtered) {
    if ([root isKindOfClass:NSMutableArray.class]) {
        NSMutableArray *array = root;
        BOOL looks = NO;
        for (id item in array) if ([item isKindOfClass:NSDictionary.class] && ZZLooksLikeProductDictionary(item)) { looks = YES; break; }
        if (looks) { [array removeAllObjects]; [array addObjectsFromArray:filtered]; return YES; }
        for (id child in [array copy]) if (ZZReplaceFirstProductArray(child, filtered)) return YES;
        return NO;
    }
    if (![root isKindOfClass:NSMutableDictionary.class]) return NO;
    NSMutableDictionary *dict = root;
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products", @"data"]) {
        id child = dict[key];
        if (ZZReplaceFirstProductArray(child, filtered)) return YES;
    }
    for (NSString *key in dict.allKeys) if (ZZReplaceFirstProductArray(dict[key], filtered)) return YES;
    return NO;
}

static NSArray *ZZFilterProducts(NSArray *products, NSUInteger *knownOut) {
    ZZSettings *settings = ZZSettings.shared;
    ZZProductFilter *filter = [ZZProductFilter new];
    filter.enabled = YES;
    filter.minimumVersion = settings.minimumVersion ?: @"";
    filter.maximumVersion = settings.maximumVersion ?: @"";
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:products.count];
    for (id obj in products) {
        if (![obj isKindOfClass:NSDictionary.class]) { [result addObject:obj]; continue; }
        NSDictionary *d = obj;
        NSString *version = ZZProductVersionFromDictionary(d);
        BOOL keep = YES;
        if (version.length) {
            if (knownOut) *knownOut += 1;
            keep = [filter shouldDisplayProduct:d];
        } else {
            NSString *pid = ZZProductIDFromInfo(d);
            keep = pid.length ? [[ZZProductVisibility shared] shouldDisplayProductID:pid] : (!settings.minimumVersion.length && !settings.maximumVersion.length);
        }
        if (keep) [result addObject:d];
    }
    return result.copy;
}

static void ZZWaitForDetailEnrichment(NSArray<NSString *> *ids, NSDictionary<NSString *,NSURL *> *jumpURLs, NSURLRequest *sourceRequest) {
    if (!ids.count) return;
    NSMutableArray<NSString *> *todo = [NSMutableArray array];
    for (NSString *pid in ids) {
        if (![[ZZProductVisibility shared] cachedVersionForProductID:pid].length) [todo addObject:pid];
        if (todo.count >= 12) break;
    }
    if (!todo.count) return;

    NSURL *baseURL = [NSURL URLWithString:@"https://app.zhuanzhuan.com/zzopen/waresshow/moreInfo"];
    if (!baseURL) return;

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSDictionary *headers = sourceRequest.allHTTPHeaderFields ?: @{};
    ZZDetailPrefetchCount += todo.count;
    ZZDetailFetcher *fetcher = [ZZDetailFetcher shared];
    [fetcher fetchDetailsForProductIDs:todo jumpURLsByProductID:jumpURLs sourceRequest:sourceRequest baseURL:baseURL headers:headers completion:^(NSArray<NSDictionary *> *entries, NSError *error) {
        ZZDetailPrefetchEntryCount += entries.count;
        for (NSDictionary *entry in entries) {
            NSString *pid = ZZProductIDFromInfo(entry);
            if (pid.length && ZZProductVersionFromDictionary(entry).length) [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[pid]];
        }
        ZZFilterDebugWrite(@"[ZZFilterDetail] complete requested=%lu resolved=%lu error=%@",
                           (unsigned long)todo.count, (unsigned long)entries.count,
                           error.localizedDescription ?: @"none");
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
}

+ (NSData *)filteredJSONData:(NSData *)data
                   sourceURL:(NSURL *)sourceURL
               sourceRequest:(NSURLRequest *)sourceRequest
                       error:(NSError **)error {
    if (!data.length) return data;
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (!root) return data;

    BOOL isDetail = [sourceURL.path.lowercaseString containsString:@"waresshow/moreinfo"];
    NSString *fallbackPID = ZZFallbackProductIDFromRequest(sourceRequest);
    NSUInteger learned = 0;

    // IMPORTANT: learning happens even when no range is configured. v24 returned
    // early before collecting anything, which is why its result rows had no iOS
    // version at all. The cache is now built continuously from list/detail traffic.
    ZZCollectVersionEntries(root, fallbackPID, 0, &learned);
    if (isDetail) {
        ZZFilterDebugWrite(@"[ZZFilterNetwork] detail learned=%lu pid=%@ url=%@", (unsigned long)learned, fallbackPID, sourceURL.absoluteString ?: @"");
        return data;
    }

    NSString *path = nil;
    NSArray *products = ZZFindProductArray(root, &path);
    if (!products) {
        ZZFilterDebugWrite(@"[ZZFilterNetwork] list JSON no product array bytes=%lu learned=%lu url=%@", (unsigned long)data.length, (unsigned long)learned, sourceURL.absoluteString ?: @"");
        return data;
    }

    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:products.count];
    NSMutableDictionary<NSString *,NSURL *> *jumpURLs = [NSMutableDictionary dictionary];
    for (id obj in products) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *d = obj;
        NSString *pid = ZZProductIDFromInfo(d);
        if (!pid.length) continue;
        [[ZZProductVisibility shared] recordEntries:@[d] forProductIDs:@[pid]];
        if (![ids containsObject:pid]) [ids addObject:pid];
        NSString *cachedURL = [[ZZProductVisibility shared] cachedURLForProductID:pid];
        if (cachedURL.length) {
            NSURL *jump = [NSURL URLWithString:cachedURL];
            if (jump) jumpURLs[pid] = jump;
        }
    }

    NSUInteger knownBefore = 0;
    NSArray *filtered = ZZFilterProducts(products, &knownBefore);
    if (ids.count) {
        ZZWaitForDetailEnrichment(ids, jumpURLs, sourceRequest);
        NSUInteger knownAfter = 0;
        filtered = ZZFilterProducts(products, &knownAfter);
        knownBefore = knownAfter;
    }

    ZZSettings *settings = ZZSettings.shared;
    BOOL rangeConfigured = settings.minimumVersion.length || settings.maximumVersion.length;
    BOOL changed = filtered.count != products.count;
    ZZFilterDebugWrite(@"[ZZFilterNetwork] list path=%@ before=%lu after=%lu known=%lu learned=%lu ids=%lu range=%@~%@ enabled=%d",
                       path ?: @"?", (unsigned long)products.count, (unsigned long)filtered.count,
                       (unsigned long)knownBefore, (unsigned long)learned, (unsigned long)ids.count,
                       settings.minimumVersion.length ? settings.minimumVersion : @"不限",
                       settings.maximumVersion.length ? settings.maximumVersion : @"不限",
                       settings.enabled);

    // With no range, preserve the original server response. The cache/result
    // page is still populated, so system versions can be shown independently.
    if (!settings.enabled || !rangeConfigured) return data;
    if (!changed) return data;
    if (!ZZReplaceFirstProductArray(root, filtered)) return data;
    ZZNetworkModifiedCount += 1;
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error] ?: data;
}

+ (NSData *)filteredJSONData:(NSData *)data error:(NSError **)error {
    return [self filteredJSONData:data sourceURL:nil sourceRequest:nil error:error];
}

- (void)startLoading {
    NSMutableURLRequest *request = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:request];
    self.sourceRequest = request.copy;
    self.responseData = [NSMutableData data];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.protocolClasses = @[];
    configuration.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    configuration.HTTPShouldSetCookies = YES;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:request];
    ZZNetworkInterceptedCount += 1;
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
    self.responseData = nil;
    self.receivedResponse = nil;
    self.sourceRequest = nil;
    self.shouldProcessResponse = NO;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.receivedResponse = response;
    self.shouldProcessResponse = NO;
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        ZZStoreResponseCookies(http, response.URL ?: self.sourceRequest.URL);
        NSString *contentType = http.allHeaderFields[@"Content-Type"];
        NSString *urlString = response.URL.absoluteString.lowercaseString ?: @"";
        NSString *ct = contentType.lowercaseString ?: @"";
        self.shouldProcessResponse = [ct containsString:@"json"] || [urlString containsString:@"moreinfo"] || [urlString containsString:@"search"];
    }
    completionHandler(NSURLSessionResponseAllow);
    if (!self.shouldProcessResponse && response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    (void)session; (void)dataTask;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (self.shouldProcessResponse) [self.responseData appendData:data];
    else if (data.length) [self.client URLProtocol:self didLoadData:data];
    (void)session; (void)dataTask;
}

- (NSURLResponse *)responseByRemovingEncodingAndLength:(NSURLResponse *)response {
    if (![response isKindOfClass:NSHTTPURLResponse.class]) return response;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSMutableDictionary *headers = [http.allHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in @[@"Content-Length", @"content-length", @"Content-Encoding", @"content-encoding"]) [headers removeObjectForKey:key];
    return [[NSHTTPURLResponse alloc] initWithURL:http.URL statusCode:http.statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else if (!self.shouldProcessResponse) {
        [self.client URLProtocolDidFinishLoading:self];
    } else {
        NSError *filterError = nil;
        NSData *original = self.responseData ?: [NSData data];
        NSData *output = [self.class filteredJSONData:original sourceURL:self.receivedResponse.URL sourceRequest:self.sourceRequest error:&filterError] ?: original;
        BOOL modified = ![output isEqualToData:original];
        NSURLResponse *response = modified ? [self responseByRemovingEncodingAndLength:self.receivedResponse] : self.receivedResponse;
        if (response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (output.length) [self.client URLProtocol:self didLoadData:output];
        [self.client URLProtocolDidFinishLoading:self];
        if (modified) NSLog(@"[ZZFilterNetwork] response modified %lu -> %lu", (unsigned long)original.length, (unsigned long)output.length);
        if (filterError) ZZFilterDebugWrite(@"[ZZFilterNetwork] JSON error %@", filterError.localizedDescription ?: @"");
    }
    self.task = nil;
    self.responseData = nil;
    self.receivedResponse = nil;
    self.sourceRequest = nil;
    self.shouldProcessResponse = NO;
    (void)session; (void)task;
}
@end
