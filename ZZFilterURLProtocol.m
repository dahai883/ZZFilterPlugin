#import "ZZFilterURLProtocol.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"
#import "ZZDebug.h"
#import "ZZProductVisibility.h"
#import "ZZDetailFetcher.h"

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
           [path containsString:@"waresshow/moreinfo"] ||
           [path containsString:@"waresshow/moreInfo"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }

+ (void)installOnSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    if (![classes containsObject:self]) [classes insertObject:self atIndex:0];
    configuration.protocolClasses = classes;
}

static NSArray *ZZFindProductArray(id root, NSString **pathOut) {
    if ([root isKindOfClass:NSArray.class]) {
        NSArray *array = root;
        NSUInteger hits = 0;
        for (id item in array) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *d = item;
            if (d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"itemId"] || d[@"title"] || d[@"name"]) hits++;
            if (hits >= 1) break;
        }
        if (hits) {
            if (pathOut) *pathOut = @"$";
            return array;
        }
        return nil;
    }
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dict = root;
    NSArray *preferred = @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products", @"data"];
    for (NSString *key in preferred) {
        id value = dict[key];
        NSString *childPath = nil;
        NSArray *found = ZZFindProductArray(value, &childPath);
        if (found) {
            if (pathOut) *pathOut = [NSString stringWithFormat:@"$.%@%@", key, childPath.length && ![childPath isEqualToString:@"$"] ? [childPath substringFromIndex:1] : @""];
            return found;
        }
    }
    for (NSString *key in dict) {
        id value = dict[key];
        if (![value isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSArray.class]) continue;
        NSArray *found = ZZFindProductArray(value, NULL);
        if (found) {
            if (pathOut) *pathOut = [NSString stringWithFormat:@"$.%@", key];
            return found;
        }
    }
    return nil;
}

static void ZZCollectVersionEntries(id root, NSUInteger depth, NSUInteger *countOut) {
    if (depth > 7 || !root) return;
    if ([root isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)root;
        NSString *pid = ZZProductIDFromInfo(d);
        NSString *version = ZZProductVersionFromDictionary(d);
        if (pid.length && version.length) {
            [[ZZProductVisibility shared] recordEntries:@[d] forProductIDs:@[pid]];
            if (countOut) *countOut += 1;
        }
        // Detail payloads may store attributes under itemId2AttrInfo, where the
        // product ID is the dictionary key rather than an `id` field. Preserve
        // that association before descending.
        id attrMap = d[@"itemId2AttrInfo"];
        if ([attrMap isKindOfClass:NSDictionary.class]) {
            for (NSString *mappedID in (NSDictionary *)attrMap) {
                id mapped = ((NSDictionary *)attrMap)[mappedID];
                if (![mapped isKindOfClass:NSDictionary.class]) continue;
                NSMutableDictionary *entry = [mapped mutableCopy];
                if (!ZZProductIDFromInfo(entry).length && mappedID.length) entry[@"productId"] = mappedID;
                NSString *v = ZZProductVersionFromDictionary(entry);
                if (v.length) {
                    [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[mappedID]];
                    if (countOut) *countOut += 1;
                }
                ZZCollectVersionEntries(entry, depth + 1, countOut);
            }
        }
        for (NSString *key in d) {
            if ([key isEqualToString:@"itemId2AttrInfo"]) continue;
            id value = d[key];
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                ZZCollectVersionEntries(value, depth + 1, countOut);
            }
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)root) {
            if ([item isKindOfClass:NSDictionary.class] || [item isKindOfClass:NSArray.class]) {
                ZZCollectVersionEntries(item, depth + 1, countOut);
            }
        }
    }
}

static void ZZCollectProductIDs(id root, NSMutableArray<NSString *> *ids, NSUInteger depth) {
    if (depth > 5 || ids.count >= 24 || !root) return;
    if ([root isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)root;
        NSString *pid = ZZProductIDFromInfo(d);
        if (pid.length && ![ids containsObject:pid]) [ids addObject:pid];
        for (id value in d.allValues) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                ZZCollectProductIDs(value, ids, depth + 1);
                if (ids.count >= 24) return;
            }
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)root) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                ZZCollectProductIDs(value, ids, depth + 1);
                if (ids.count >= 24) return;
            }
        }
    }
}

static BOOL ZZReplaceFirstProductArray(id root, NSArray *filtered) {
    if ([root isKindOfClass:NSMutableArray.class]) {
        NSMutableArray *array = (NSMutableArray *)root;
        BOOL looks = NO;
        for (id item in array) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *d = item;
            if (d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"itemId"] || d[@"title"] || d[@"name"]) { looks = YES; break; }
        }
        if (looks) {
            [array removeAllObjects];
            [array addObjectsFromArray:filtered];
            return YES;
        }
        for (id child in [array copy]) if (ZZReplaceFirstProductArray(child, filtered)) return YES;
        return NO;
    }
    if (![root isKindOfClass:NSMutableDictionary.class]) return NO;
    NSMutableDictionary *dict = (NSMutableDictionary *)root;
    for (NSString *key in @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products", @"data"]) {
        id child = dict[key];
        if (ZZReplaceFirstProductArray(child, filtered)) return YES;
    }
    for (NSString *key in dict.allKeys) {
        id child = dict[key];
        if (ZZReplaceFirstProductArray(child, filtered)) return YES;
    }
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
        NSDictionary *d = (NSDictionary *)obj;
        NSString *version = ZZProductVersionFromDictionary(d);
        BOOL keep = YES;
        if (version.length) {
            if (knownOut) *knownOut += 1;
            keep = [filter shouldDisplayProduct:d];
        } else {
            NSString *pid = ZZProductIDFromInfo(d);
            // Strict version mode: after attempting detail enrichment, an
            // unversioned card cannot be treated as a match. This prevents
            // the listing from showing products outside the requested range.
            if (settings.minimumVersion.length || settings.maximumVersion.length) {
                keep = pid.length ? [[ZZProductVisibility shared] shouldDisplayProductID:pid] : NO;
            } else {
                keep = YES;
            }
        }
        if (keep) [result addObject:obj];
    }
    return result;
}

static void ZZWaitForDetailEnrichment(NSArray<NSString *> *ids, NSURLRequest *sourceRequest) {
    if (!ids.count) return;
    NSURL *baseURL = [NSURL URLWithString:@"https://app.zhuanzhuan.com/zzopen/waresshow/moreInfo"];
    if (!baseURL) return;

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSDictionary *headers = sourceRequest.allHTTPHeaderFields ?: @{};
    ZZDetailPrefetchCount += MIN((NSUInteger)12, ids.count);
    ZZDetailFetcher *fetcher = [ZZDetailFetcher new];
    [fetcher fetchDetailsForProductIDs:ids baseURL:baseURL headers:headers completion:^(NSArray<NSDictionary *> *entries, NSError *error) {
        ZZDetailPrefetchEntryCount += entries.count;
        for (NSDictionary *entry in entries) {
            NSString *pid = ZZProductIDFromInfo(entry);
            if (pid.length && ZZProductVersionFromDictionary(entry).length) {
                [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[pid]];
            }
        }
        ZZFilterDebugWrite(@"[ZZFilterDetail] completed ids=%lu entries=%lu error=%@",
                           (unsigned long)ids.count, (unsigned long)entries.count,
                           error.localizedDescription ?: @"none");
        dispatch_semaphore_signal(done);
    }];
    // Bound the added latency. If the detail service is slow/unavailable, the
    // original list response is still delivered and the cache can be filled
    // for a later refresh.
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)));
}

+ (NSData *)filteredJSONData:(NSData *)data
                   sourceURL:(NSURL *)sourceURL
               sourceRequest:(NSURLRequest *)sourceRequest
                       error:(NSError **)error {
    if (!data.length) return data;
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (!root) return nil;

    ZZSettings *settings = ZZSettings.shared;
    if (!settings.enabled || (!settings.minimumVersion.length && !settings.maximumVersion.length)) return data;

    BOOL isDetail = [sourceURL.path.lowercaseString containsString:@"waresshow/moreinfo"];
    NSUInteger learned = 0;
    ZZCollectVersionEntries(root, 0, &learned);
    if (isDetail) {
        ZZFilterDebugWrite(@"[ZZFilterNetwork] detail response learned=%lu url=%@", (unsigned long)learned, sourceURL.absoluteString ?: @"");
        return data;
    }

    NSString *path = nil;
    NSArray *products = ZZFindProductArray(root, &path);
    if (!products) {
        ZZFilterDebugWrite(@"[ZZFilterNetwork] list JSON no product array bytes=%lu learned=%lu url=%@",
                           (unsigned long)data.length, (unsigned long)learned, sourceURL.absoluteString ?: @"");
        return data;
    }

    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:products.count];
    // Keep the original listing object (especially jumpUrl) in the cache even
    // when the listing card itself has no system-version field. The detail
    // response is merged into this object later, so result rows can retain a
    // real navigational link instead of displaying an ID-only record.
    for (id obj in products) {
        if ([obj isKindOfClass:NSDictionary.class]) {
            NSString *pid = ZZProductIDFromInfo(obj);
            if (pid.length) {
                [[ZZProductVisibility shared] recordEntries:@[obj] forProductIDs:@[pid]];
                if (![ids containsObject:pid]) [ids addObject:pid];
            }
        }
    }

    NSUInteger knownBefore = 0;
    NSArray *filtered = ZZFilterProducts(products, &knownBefore);

    // The search cards often do not carry the "系统版本" field; it is present
    // in the product detail response instead. Enrich only when necessary.
    if (knownBefore < products.count && ids.count) {
        ZZWaitForDetailEnrichment(ids, sourceRequest);
        NSUInteger knownAfter = 0;
        filtered = ZZFilterProducts(products, &knownAfter);
        knownBefore = knownAfter;
    }

    BOOL changed = filtered.count != products.count;
    ZZFilterDebugWrite(@"[ZZFilterNetwork] version filter path=%@ before=%lu after=%lu known=%lu learned=%lu ids=%lu range=%@~%@",
                       path ?: @"?", (unsigned long)products.count, (unsigned long)filtered.count,
                       (unsigned long)knownBefore, (unsigned long)learned, (unsigned long)ids.count,
                       settings.minimumVersion.length ? settings.minimumVersion : @"不限",
                       settings.maximumVersion.length ? settings.maximumVersion : @"不限");
    if (!changed) return data;
    if (!ZZReplaceFirstProductArray(root, filtered)) return data;
    ZZNetworkModifiedCount += 1;
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
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
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:request];
    ZZNetworkInterceptedCount += 1;
    NSLog(@"[ZZFilterNetwork] INTERCEPT %@ %@", request.HTTPMethod ?: @"GET", request.URL.absoluteString ?: @"");
    ZZFilterDebugWrite(@"[ZZFilterNetwork] INTERCEPT %@ host=%@ path=%@", request.HTTPMethod ?: @"GET", request.URL.host ?: @"", request.URL.path ?: @"/");
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
        NSString *contentType = [((NSHTTPURLResponse *)response).allHeaderFields objectForKey:@"Content-Type"];
        NSString *urlString = response.URL.absoluteString.lowercaseString ?: @"";
        NSString *ct = contentType.lowercaseString ?: @"";
        self.shouldProcessResponse = [ct containsString:@"json"] || [urlString containsString:@"moreinfo"] || [urlString containsString:@"search"];
    }
    completionHandler(NSURLSessionResponseAllow);
    if (!self.shouldProcessResponse && response) {
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    }
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
        ZZFilterDebugWrite(@"[ZZFilterNetwork] request failed %@", error.localizedDescription ?: @"");
        [self.client URLProtocol:self didFailWithError:error];
    } else if (!self.shouldProcessResponse) {
        [self.client URLProtocolDidFinishLoading:self];
    } else {
        NSError *filterError = nil;
        NSData *original = self.responseData ?: [NSData data];
        NSData *output = [self.class filteredJSONData:original sourceURL:self.receivedResponse.URL sourceRequest:self.sourceRequest error:&filterError];
        if (!output) output = original;
        BOOL modified = ![output isEqualToData:original];
        NSURLResponse *response = modified ? [self responseByRemovingEncodingAndLength:self.receivedResponse] : self.receivedResponse;
        if (response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (output.length) [self.client URLProtocol:self didLoadData:output];
        [self.client URLProtocolDidFinishLoading:self];
        NSLog(@"[ZZFilterNetwork] COMPLETE modified=%@ bytes=%lu->%lu", modified ? @"YES" : @"NO", (unsigned long)original.length, (unsigned long)output.length);
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
