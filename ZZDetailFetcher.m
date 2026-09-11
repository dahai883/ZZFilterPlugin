#import "ZZDetailFetcher.h"

@implementation ZZDetailFetcher

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.HTTPAdditionalHeaders = @{@"Accept": @"application/json"};
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
                              baseURL:(NSURL *)baseURL
                          completion:(ZZDetailCompletion)completion {
    if (!completion) return;
    if (productIDs.count == 0) {
        completion(@[], nil);
        return;
    }

    NSMutableArray *entries = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    __block NSError *firstError = nil;

    for (NSString *pid in productIDs) {
        if (![pid isKindOfClass:NSString.class] || pid.length == 0) continue;

        dispatch_group_enter(group);
        NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
        NSMutableArray *items = [components.queryItems mutableCopy] ?: [NSMutableArray array];
        [items addObject:[NSURLQueryItem queryItemWithName:@"productId" value:pid]];
        components.queryItems = items;

        NSURLRequest *request = [NSURLRequest requestWithURL:components.URL ?: baseURL];
        NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error && !firstError) firstError = error;

            if (data.length > 0 && !error) {
                id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([obj isKindOfClass:NSDictionary.class]) {
                    @synchronized (entries) {
                        [entries addObject:obj];
                    }
                } else if ([obj isKindOfClass:NSArray.class]) {
                    @synchronized (entries) {
                        for (id item in obj) {
                            if ([item isKindOfClass:NSDictionary.class]) [entries addObject:item];
                        }
                    }
                }
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion(entries.copy, firstError);
    });
}

@end
