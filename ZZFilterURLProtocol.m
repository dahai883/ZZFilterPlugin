#import "ZZFilterURLProtocol.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"

static NSString * const kHandledKey = @"ZZFilterHandledRequest";

@interface ZZFilterURLProtocol () <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *responseData;
@property(nonatomic, strong) NSURLResponse *receivedResponse;
@end

@implementation ZZFilterURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return NO;
    return YES;
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
        for (id item in array) {
            if ([item isKindOfClass:NSDictionary.class]) {
                NSDictionary *d = item;
                if (d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"title"] || d[@"name"]) {
                    if (pathOut) *pathOut = @"$";
                    return array;
                }
            }
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
            if (pathOut) *pathOut = [NSString stringWithFormat:@"%@.%@", @"$", key];
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

static BOOL ZZReplaceFirstProductArray(id root, NSArray *filtered) {
    if ([root isKindOfClass:NSMutableArray.class]) {
        NSMutableArray *array = root;
        BOOL looks = NO;
        for (id item in array) {
            if ([item isKindOfClass:NSDictionary.class]) {
                NSDictionary *d = item;
                if (d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"title"] || d[@"name"]) { looks = YES; break; }
            }
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
    NSMutableDictionary *dict = root;
    NSArray *preferred = @[@"items", @"list", @"results", @"infos", @"itemsArray", @"goods", @"products", @"data"];
    for (NSString *key in preferred) {
        id child = dict[key];
        if (ZZReplaceFirstProductArray(child, filtered)) return YES;
    }
    for (NSString *key in dict.allKeys) {
        id child = dict[key];
        if (ZZReplaceFirstProductArray(child, filtered)) return YES;
    }
    return NO;
}

+ (NSData *)filteredJSONData:(NSData *)data error:(NSError **)error {
    if (!data.length) return data;
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (!root) return nil;

    ZZSettings *settings = ZZSettings.shared;
    if (!settings.enabled) {
        NSLog(@"[ZZFilterNetwork] filter disabled; pass-through");
        return data;
    }

    NSString *path = nil;
    NSArray *products = ZZFindProductArray(root, &path);
    if (!products) {
        NSLog(@"[ZZFilterNetwork] JSON received but no product array found bytes=%lu", (unsigned long)data.length);
        return data;
    }

    ZZProductFilter *filter = [ZZProductFilter new];
    filter.enabled = settings.enabled;
    filter.minimumText = settings.minimumText;
    filter.maximumText = settings.maximumText;
    filter.minimumVersion = settings.minimumVersion;
    filter.maximumVersion = settings.maximumVersion;

    NSArray *filtered = [filter filteredProducts:products];
    NSLog(@"[ZZFilterNetwork] product array path=%@ before=%lu after=%lu min=%ld max=%ld minVer=%@ maxVer=%@",
          path ?: @"?", (unsigned long)products.count, (unsigned long)filtered.count,
          (long)settings.minimumText, (long)settings.maximumText,
          settings.minimumVersion, settings.maximumVersion);

    if (filtered.count == products.count) return data;
    if (!ZZReplaceFirstProductArray(root, filtered)) return data;
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

- (void)startLoading {
    NSMutableURLRequest *request = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:request];
    self.responseData = [NSMutableData data];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    // The automatic configuration hook will also install this protocol. The
    // handled-request marker above prevents recursion.
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:request];
    NSLog(@"[ZZFilterNetwork] INTERCEPT request %@ %@", request.HTTPMethod ?: @"GET", request.URL.absoluteString);
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
    self.responseData = nil;
    self.receivedResponse = nil;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.receivedResponse = response;
    completionHandler(NSURLSessionResponseAllow);
    (void)session; (void)dataTask;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    (void)session; (void)dataTask;
}

- (NSURLResponse *)responseByRemovingEncodingAndLength:(NSURLResponse *)response {
    if (![response isKindOfClass:NSHTTPURLResponse.class]) return response;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSMutableDictionary *headers = [http.allHeaderFields mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in @[@"Content-Length", @"content-length", @"Content-Encoding", @"content-encoding"]) {
        [headers removeObjectForKey:key];
    }
    return [[NSHTTPURLResponse alloc] initWithURL:http.URL
                                        statusCode:http.statusCode
                                       HTTPVersion:@"HTTP/1.1"
                                      headerFields:headers];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"[ZZFilterNetwork] request failed %@", error);
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        NSError *filterError = nil;
        NSData *original = self.responseData ?: [NSData data];
        NSData *output = [self.class filteredJSONData:original error:&filterError];
        BOOL modified = output && ![output isEqualToData:original];
        if (!output) output = original;

        NSURLResponse *response = modified ? [self responseByRemovingEncodingAndLength:self.receivedResponse] : self.receivedResponse;
        if (response) {
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        }
        [self.client URLProtocol:self didLoadData:output];
        [self.client URLProtocolDidFinishLoading:self];
        NSLog(@"[ZZFilterNetwork] COMPLETE modified=%@ bytes=%lu->%lu",
              modified ? @"YES" : @"NO", (unsigned long)original.length, (unsigned long)output.length);
        if (filterError) NSLog(@"[ZZFilterNetwork] JSON error %@", filterError.localizedDescription);
    }
    self.task = nil;
    self.responseData = nil;
    self.receivedResponse = nil;
    (void)session; (void)task;
}

@end
