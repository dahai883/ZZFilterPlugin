#import "ZZNetworkInterception.h"
#import "ZZFilterURLProtocol.h"
#import <objc/runtime.h>
#import "ZZProductFilter.h"
#import "ZZProductVisibility.h"
#import "ZZDebug.h"

static NSMutableArray<NSHTTPCookieStorage *> *gCookieStorages;
static NSObject *gCookieLock;
static NSUInteger gDetailCapturedEntries;
static NSUInteger gObservedDetailRequests;
static NSObject *gDetailCaptureLock;
static NSObject *gObservedRequestLock;

NSUInteger ZZDetailCapturedEntries(void) {
    @synchronized (gDetailCaptureLock ?: [NSObject class]) { return gDetailCapturedEntries; }
}

static void ZZEnsureDetailCaptureLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gDetailCaptureLock = [NSObject new]; });
}

static void ZZEnsureObservedRequestLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gObservedRequestLock = [NSObject new]; });
}

static NSString *ZZRequestValue(NSURLRequest *request, NSArray<NSString *> *names) {
    NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in c.queryItems ?: @[]) {
        for (NSString *name in names) {
            if ([item.name caseInsensitiveCompare:name] == NSOrderedSame && item.value.length) return item.value;
        }
    }
    NSData *body = request.HTTPBody;
    if (body.length) {
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        if (text.length) {
            NSString *decoded = [text stringByRemovingPercentEncoding] ?: text;
            for (NSString *name in names) {
                NSString *needle = [NSString stringWithFormat:@"%@=", name];
                NSRange r = [decoded rangeOfString:needle options:NSCaseInsensitiveSearch];
                if (r.location != NSNotFound) {
                    NSString *tail = [decoded substringFromIndex:NSMaxRange(r)];
                    NSRange amp = [tail rangeOfString:@"&"];
                    if (amp.location != NSNotFound) tail = [tail substringToIndex:amp.location];
                    if (tail.length) return [tail stringByRemovingPercentEncoding] ?: tail;
                }
            }
            id obj = [NSJSONSerialization JSONObjectWithData:[decoded dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            if ([obj isKindOfClass:NSDictionary.class]) {
                NSDictionary *d = obj;
                for (NSString *name in names) {
                    id value = d[name];
                    if ([value isKindOfClass:NSString.class] && [value length]) return value;
                    if ([value respondsToSelector:@selector(stringValue)] && [value stringValue].length) return [value stringValue];
                }
            }
        }
    }
    return @"";
}

static NSString *ZZProductIDFromRequest(NSURLRequest *request) {
    return ZZRequestValue(request, @[@"productId", @"productID", @"goodsId", @"itemId", @"infoId", @"strInfoId", @"item_id", @"goods_id"]);
}

static BOOL ZZLooksLikeDetailRequest(NSURLRequest *request) {
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString ?: @"";
    if (!([host hasSuffix:@"zhuanzhuan.com"] || [host hasSuffix:@"zhuanzhuan.com.cn"])) return NO;
    NSString *path = url.path.lowercaseString ?: @"";
    if ([path containsString:@"/zz/transfer/search"] || [path containsString:@"transmitparamsearch"] || [path containsString:@"/search"]) return NO;
    NSString *pid = ZZProductIDFromRequest(request);
    if (pid.length) return YES;
    return [path containsString:@"detail"] || [path containsString:@"moreinfo"] || [path containsString:@"waresshow"] || [path containsString:@"goods"] || [path containsString:@"item"];
}

static void ZZCaptureDetailObject(id obj, NSString *fallbackPID, NSUInteger depth) {
    if (depth > 14 || !obj) return;
    if ([obj isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:NULL];
            if (parsed) ZZCaptureDetailObject(parsed, fallbackPID, depth + 1);
        }
        return;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = obj;
        NSString *pid = nil;
        for (NSString *k in @[@"productId", @"productID", @"goodsId", @"itemId", @"infoId", @"strInfoId", @"id"]) {
            id v = d[k];
            if ([v isKindOfClass:NSString.class] && [v length]) { pid = v; break; }
            if ([v respondsToSelector:@selector(stringValue)] && [v stringValue].length) { pid = [v stringValue]; break; }
        }
        if (!pid.length) pid = fallbackPID;
        NSString *version = ZZProductVersionFromDictionary(d);
        if (pid.length && version.length) {
            NSMutableDictionary *entry = [d mutableCopy];
            entry[@"productId"] = pid;
            [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[pid]];
            ZZEnsureDetailCaptureLock();
            @synchronized (gDetailCaptureLock) { gDetailCapturedEntries += 1; }
        }
        id map = d[@"itemId2AttrInfo"];
        if (map) ZZCaptureDetailObject(map, pid ?: fallbackPID, depth + 1);
        for (NSString *key in d) {
            if ([key isEqualToString:@"itemId2AttrInfo"]) continue;
            id value = d[key];
            if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class] || [value isKindOfClass:NSString.class]) ZZCaptureDetailObject(value, pid ?: fallbackPID, depth + 1);
        }
    } else if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) ZZCaptureDetailObject(child, fallbackPID, depth + 1);
    }
}

static void ZZObserveDetailResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error) {
    if (error || !data.length) return;
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (status < 200 || status >= 300) return;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    if (!obj) return;
    NSUInteger before = ZZDetailCapturedEntries();
    ZZCaptureDetailObject(obj, ZZProductIDFromRequest(request), 0);
    NSUInteger after = ZZDetailCapturedEntries();
    if (after > before) ZZFilterDebugWrite(@"[ZZDetailObserver] captured=%lu method=%@ status=%ld pid=%@ url=%@", (unsigned long)(after-before), request.HTTPMethod ?: @"GET", (long)status, ZZProductIDFromRequest(request), request.URL.absoluteString ?: @"");
}

static NSURLSessionDataTask *(*gOrigDataTaskWithCompletion)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *(*gOrigDataTask)(id, SEL, NSURLRequest *);

static NSURLSession *ZZObserverSession(void) {
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.protocolClasses = @[];
        cfg.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    if (!gOrigDataTaskWithCompletion) return nil;
    NSURLSessionDataTask *task = gOrigDataTaskWithCompletion(self, _cmd, request, completion);
    if (ZZLooksLikeDetailRequest(request)) {
        @synchronized (gObservedRequestLock) { if (gObservedDetailRequests < 24) gObservedDetailRequests += 1; else return task; }
        NSURLRequest *copy = request.copy;
        NSURLSession *observer = ZZObserverSession();
        gOrigDataTaskWithCompletion(observer, @selector(dataTaskWithRequest:completionHandler:), copy, ^(NSData *data, NSURLResponse *response, NSError *error) {
            ZZObserveDetailResponse(copy, data, response, error);
        }).resume;
    }
    return task;
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (!gOrigDataTask) return nil;
    NSURLSessionDataTask *task = gOrigDataTask(self, _cmd, request);
    if (ZZLooksLikeDetailRequest(request)) {
        @synchronized (gObservedRequestLock) { if (gObservedDetailRequests < 24) gObservedDetailRequests += 1; else return task; }
        NSURLRequest *copy = request.copy;
        NSURLSession *observer = ZZObserverSession();
        gOrigDataTaskWithCompletion(observer, @selector(dataTaskWithRequest:completionHandler:), copy, ^(NSData *data, NSURLResponse *response, NSError *error) {
            ZZObserveDetailResponse(copy, data, response, error);
        }).resume;
    }
    return task;
}


static void ZZEnsureCookieRegistry(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCookieStorages = [NSMutableArray array];
        gCookieLock = [NSObject new];
    });
}

void ZZRegisterCookieStorage(NSHTTPCookieStorage *storage) {
    if (!storage) return;
    ZZEnsureCookieRegistry();
    @synchronized (gCookieLock) {
        if (![gCookieStorages containsObject:storage]) [gCookieStorages addObject:storage];
    }
}

NSArray<NSHTTPCookieStorage *> *ZZRegisteredCookieStorages(void) {
    ZZEnsureCookieRegistry();
    @synchronized (gCookieLock) { return gCookieStorages.copy; }
}

NSArray<NSHTTPCookie *> *ZZCookiesForURL(NSURL *url) {
    if (!url) return @[];
    NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^appendCookies)(NSArray<NSHTTPCookie *> *) = ^(NSArray<NSHTTPCookie *> *items) {
        for (NSHTTPCookie *cookie in items ?: @[]) {
            NSString *identity = [NSString stringWithFormat:@"%@|%@|%@|%@",
                                  cookie.name ?: @"", cookie.domain ?: @"", cookie.path ?: @"", cookie.value ?: @""];
            if (![seen containsObject:identity]) {
                [seen addObject:identity];
                [cookies addObject:cookie];
            }
        }
    };

    appendCookies([NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:url]);
    for (NSHTTPCookieStorage *storage in ZZRegisteredCookieStorages()) {
        appendCookies([storage cookiesForURL:url]);
    }
    return cookies.copy;
}

void ZZStoreResponseCookies(NSHTTPURLResponse *response, NSURL *url) {
    if (!response || !url) return;
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:url];
    if (!cookies.count) return;
    [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookies:cookies forURL:url mainDocumentURL:nil];
    for (NSHTTPCookieStorage *storage in ZZRegisteredCookieStorages()) {
        if (storage != NSHTTPCookieStorage.sharedHTTPCookieStorage) {
            [storage setCookies:cookies forURL:url mainDocumentURL:nil];
        }
    }
}

static void ZZAddProtocolToConfiguration(NSURLSessionConfiguration *configuration) {
    if (!configuration) return;
    ZZRegisterCookieStorage(configuration.HTTPCookieStorage);
    [ZZFilterURLProtocol installOnSessionConfiguration:configuration];
}

@interface NSURLSessionConfiguration (ZZFilterAutoInstall)
+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration;
@end

@implementation NSURLSessionConfiguration (ZZFilterAutoInstall)

+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_defaultSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] defaultSessionConfiguration intercepted; protocol installed cookieStorage=%p", configuration.HTTPCookieStorage);
    return configuration;
}

+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_ephemeralSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] ephemeralSessionConfiguration intercepted; protocol installed cookieStorage=%p", configuration.HTTPCookieStorage);
    return configuration;
}

@end

@interface NSURLSession (ZZFilterObserve)
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest_completion:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (ZZFilterObserve)
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest:(NSURLRequest *)request { return ZZ_filter_dataTaskWithRequest(self, _cmd, request); }
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest_completion:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler { return ZZ_filter_dataTaskWithRequest_completion(self, _cmd, request, completionHandler); }
@end

void ZZInstallNetworkInterception(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZZEnsureCookieRegistry();
        ZZEnsureObservedRequestLock();
        ZZRegisterCookieStorage(NSHTTPCookieStorage.sharedHTTPCookieStorage);
        Class cls = [NSURLSessionConfiguration class];
        Class sessionCls = [NSURLSession class];
        Method dataTaskWithCompletion = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:completionHandler:));
        Method replacementCompletion = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithRequest_completion:));
        if (dataTaskWithCompletion && replacementCompletion) {
            gOrigDataTaskWithCompletion = (void *)method_getImplementation(dataTaskWithCompletion);
            method_exchangeImplementations(dataTaskWithCompletion, replacementCompletion);
        }
        Method dataTaskSimple = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:));
        Method replacementSimple = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithRequest:));
        if (dataTaskSimple && replacementSimple) {
            gOrigDataTask = (void *)method_getImplementation(dataTaskSimple);
            method_exchangeImplementations(dataTaskSimple, replacementSimple);
        }

        Method originalDefault = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
        Method replacementDefault = class_getClassMethod(cls, @selector(zz_filter_defaultSessionConfiguration));
        if (originalDefault && replacementDefault) method_exchangeImplementations(originalDefault, replacementDefault);

        Method originalEphemeral = class_getClassMethod(cls, @selector(ephemeralSessionConfiguration));
        Method replacementEphemeral = class_getClassMethod(cls, @selector(zz_filter_ephemeralSessionConfiguration));
        if (originalEphemeral && replacementEphemeral) method_exchangeImplementations(originalEphemeral, replacementEphemeral);

        // Register the stores already attached to the stock configurations.
        NSURLSessionConfiguration *defaultConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSessionConfiguration *ephemeralConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        ZZRegisterCookieStorage(defaultConfig.HTTPCookieStorage);
        ZZRegisterCookieStorage(ephemeralConfig.HTTPCookieStorage);
        NSLog(@"[ZZFilterNetwork] interception installed; cookieStorages=%lu", (unsigned long)ZZRegisteredCookieStorages().count);
    });
}

__attribute__((constructor))
static void ZZNetworkInterceptionConstructor(void) {
    ZZInstallNetworkInterception();
}
