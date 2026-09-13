#import "ZZDetailFetcher.h"
#import "ZZProductVisibility.h"
#import "ZZProductFilter.h"
#import "ZZDebug.h"

@implementation ZZDetailFetcher

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        // Important: do not use the plugin's NSURLProtocol here. This session
        // is only for bounded detail enrichment and must not recurse through
        // ZZFilterURLProtocol.
        cfg.protocolClasses = @[];
        cfg.timeoutIntervalForRequest = 2.5;
        cfg.timeoutIntervalForResource = 3.5;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
                         baseURL:(NSURL *)baseURL
                       headers:(NSDictionary<NSString *,NSString *> *)headers
                    completion:(ZZDetailCompletion)completion {
    if (!completion) return;
    if (!baseURL || productIDs.count == 0) {
        completion(@[], nil);
        return;
    }

    // Keep the first-page enrichment deliberately small to avoid the CPU/
    // thermal problem seen in earlier builds.
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)12, productIDs.count)];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *pid in productIDs) {
        if (![pid isKindOfClass:NSString.class] || pid.length == 0 || [seen containsObject:pid]) continue;
        [seen addObject:pid];
        [ids addObject:pid];
        if (ids.count >= 12) break;
    }

    NSMutableArray *entries = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t slots = dispatch_semaphore_create(2);
    __block NSError *firstError = nil;

    for (NSString *pid in ids) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);

            NSURLComponents *components = [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO];
            NSMutableArray *query = [components.queryItems mutableCopy] ?: [NSMutableArray array];
            [query addObject:[NSURLQueryItem queryItemWithName:@"productId" value:pid]];
            components.queryItems = query;
            NSURL *url = components.URL;
            if (!url) {
                dispatch_semaphore_signal(slots);
                dispatch_group_leave(group);
                return;
            }

            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            request.HTTPMethod = @"GET";
            NSSet *allowedHeaders = [NSSet setWithArray:@[@"Cookie", @"Authorization", @"User-Agent", @"Accept", @"Referer", @"Origin", @"X-Requested-With"]];
            [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
                if (key.length && value.length && [allowedHeaders containsObject:key]) [request setValue:value forHTTPHeaderField:key];
                (void)stop;
            }];

            NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    @synchronized (self) { if (!firstError) firstError = error; }
                } else if (data.length) {
                    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    [self collectEntriesFromObject:obj into:entries];
                }
                dispatch_semaphore_signal(slots);
                dispatch_group_leave(group);
            }];
            [task resume];
        });
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        ZZFilterDebugWrite(@"[ZZFilterDetail] prefetch ids=%lu entries=%lu error=%@",
                           (unsigned long)ids.count, (unsigned long)entries.count,
                           firstError.localizedDescription ?: @"none");
        completion(entries.copy, firstError);
    });
}

- (void)collectEntriesFromObject:(id)obj into:(NSMutableArray *)entries {
    if (!obj) return;
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)obj;
        NSString *pid = ZZProductIDFromInfo(d);
        NSString *version = ZZProductVersionFromDictionary(d);
        if (pid.length && version.length) {
            @synchronized (entries) { [entries addObject:d]; }
        }
        id attrMap = d[@"itemId2AttrInfo"];
        if ([attrMap isKindOfClass:NSDictionary.class]) {
            for (NSString *mappedID in (NSDictionary *)attrMap) {
                id mapped = ((NSDictionary *)attrMap)[mappedID];
                if (![mapped isKindOfClass:NSDictionary.class]) continue;
                NSMutableDictionary *entry = [mapped mutableCopy];
                if (!ZZProductIDFromInfo(entry).length && mappedID.length) entry[@"productId"] = mappedID;
                NSString *v = ZZProductVersionFromDictionary(entry);
                if (v.length) {
                    @synchronized (entries) { [entries addObject:entry]; }
                }
                [self collectEntriesFromObject:entry into:entries];
            }
        }
        for (NSString *key in d) {
            if ([key isEqualToString:@"itemId2AttrInfo"]) continue;
            id value = d[key];
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                [self collectEntriesFromObject:value into:entries];
            }
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)obj) {
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
                [self collectEntriesFromObject:value into:entries];
            }
        }
    }
}

@end
