#import <objc/runtime.h>
#import "ZZFilterURLProtocol.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"

static NSString * const kHandledKey = @"ZZFilterHandledRequest";

@implementation ZZFilterURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return NO;
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (void)installOnSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    if (![classes containsObject:self]) [classes insertObject:self atIndex:0];
    configuration.protocolClasses = classes;
}

+ (NSData *)filteredJSONData:(NSData *)data error:(NSError **)error {
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    if (!root) return nil;

    ZZSettings *settings = ZZSettings.shared;
    ZZProductFilter *filter = [ZZProductFilter new];
    filter.enabled = settings.enabled;
    filter.minimumText = settings.minimumText;
    filter.maximumText = settings.maximumText;
    filter.minimumVersion = settings.minimumVersion;
    filter.maximumVersion = settings.maximumVersion;

    BOOL changed = NO;

    if ([root isKindOfClass:NSMutableDictionary.class]) {
        NSArray<NSString *> *candidateKeys = @[@"items", @"data", @"list", @"results"];
        for (NSString *key in candidateKeys) {
            id value = root[key];
            if (![value isKindOfClass:NSArray.class]) continue;

            NSArray *array = value;
            BOOL looksLikeProducts = NO;
            for (id item in array) {
                if ([item isKindOfClass:NSDictionary.class]) {
                    NSDictionary *d = item;
                    if (d[@"id"] || d[@"productId"] || d[@"goodsId"] || d[@"title"] || d[@"name"]) {
                        looksLikeProducts = YES;
                        break;
                    }
                }
            }
            if (!looksLikeProducts) continue;

            NSArray *filtered = [filter filteredProducts:array];
            if (filtered.count != array.count) {
                root[key] = [filtered mutableCopy];
                changed = YES;
            }
            break;
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        NSArray *array = root;
        NSArray *filtered = [filter filteredProducts:array];
        if (filtered.count != array.count) {
            root = [filtered mutableCopy];
            changed = YES;
        }
    }

    if (!changed) return data;
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

- (void)startLoading {
    NSMutableURLRequest *request = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:request];

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration ephemeralSessionConfiguration];

    NSURLSession *session =
        [NSURLSession sessionWithConfiguration:configuration
                                      delegate:(id<NSURLSessionDelegate>)self
                                 delegateQueue:nil];

    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request];
    objc_setAssociatedObject(self, @selector(startLoading), task, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [task resume];
}

- (void)stopLoading {
    NSURLSessionDataTask *task =
        objc_getAssociatedObject(self, @selector(startLoading));
    [task cancel];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    completionHandler(NSURLSessionResponseAllow);
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    NSError *error = nil;
    NSData *out = [self.class filteredJSONData:data error:&error];
    if (!out) out = data;
    [self.client URLProtocol:self didLoadData:out];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
    if (!error) [self.client URLProtocolDidFinishLoading:self];
    (void)session;
}

@end
