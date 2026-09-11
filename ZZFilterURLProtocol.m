#import <os/log.h>
#import "ZZFilterURLProtocol.h"
#import "ZZProductFilter.h"
#import "ZZSettings.h"

static NSString * const kHandledKey = @"ZZFilterHandledRequest";

@interface ZZFilterURLProtocol () <NSURLSessionDataDelegate>
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableData *responseData;
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
    NSUInteger beforeCount = 0;
    NSUInteger afterCount = 0;

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
            beforeCount = array.count;
            NSArray *filtered = [filter filteredProducts:array];
            afterCount = filtered.count;
            if (filtered.count != array.count) {
                root[key] = [filtered mutableCopy];
                changed = YES;
            }
            break;
        }
    } else if ([root isKindOfClass:NSArray.class]) {
        NSArray *array = root;
        beforeCount = array.count;
        NSArray *filtered = [filter filteredProducts:array];
        afterCount = filtered.count;
        if (filtered.count != array.count) {
            root = [filtered mutableCopy];
            changed = YES;
        }
    }

    os_log(OS_LOG_DEFAULT, "[ZZFilterURLProtocol] enabled=%{public}@ before=%lu after=%lu changed=%{public}@",
           settings.enabled ? @"YES" : @"NO", (unsigned long)beforeCount, (unsigned long)afterCount, changed ? @"YES" : @"NO");

    if (!changed) return data;
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

- (void)startLoading {
    NSMutableURLRequest *request = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:request];
    self.responseData = [NSMutableData data];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:request];
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
    self.responseData = nil;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
    (void)session;
    (void)dataTask;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
    (void)session;
    (void)dataTask;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        NSError *filterError = nil;
        NSData *output = [self.class filteredJSONData:self.responseData error:&filterError];
        if (!output) output = self.responseData ?: [NSData data];
        [self.client URLProtocol:self didLoadData:output];
        [self.client URLProtocolDidFinishLoading:self];
        if (filterError) {
            os_log(OS_LOG_DEFAULT, "[ZZFilterURLProtocol] JSON parse/filter error: %{public}@", filterError.localizedDescription);
        }
    }
    self.task = nil;
    self.responseData = nil;
    (void)session;
    (void)task;
}

@end
