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
static NSUInteger gObservedDetailResponses;
static NSUInteger gObservedDetail2xxResponses;
static NSUInteger gObservedDetailVersionMatches;
static NSInteger gObservedDetailLastStatusCode;
static NSString *gObservedDetailLastAllowHeader;
static NSObject *gDetailCaptureLock;
static NSObject *gObservedRequestLock;
static __thread BOOL gZZInsideObserverRequest = NO;
static const void *kZZObserverTaskKey = &kZZObserverTaskKey;
static const void *kZZObservedTaskKey = &kZZObservedTaskKey;

static void ZZEnsureDetailCaptureLock(void);
static void ZZEnsureObservedRequestLock(void);
static NSURLSession *ZZObserverSession(void);
static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request);

// All private selectors/helpers are declared before first use.
@interface NSURLSession (ZZFilterObserveForward)
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest_completion:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@interface NSURLSessionTask (ZZFilterResumeObserve)
- (void)zz_filter_resume;
@end

// Keep private category declarations and helper prototypes above every use.
// This avoids implicit declarations / missing-selector diagnostics under clang.
NSUInteger ZZDetailCapturedEntries(void) {
    ZZEnsureDetailCaptureLock();
    @synchronized (gDetailCaptureLock) { return gDetailCapturedEntries; }
}

NSUInteger ZZObservedDetailRequests(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailRequests; }
}

NSUInteger ZZObservedDetailResponses(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailResponses; }
}

NSUInteger ZZObservedDetail2xxResponses(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetail2xxResponses; }
}

NSUInteger ZZObservedDetailVersionMatches(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailVersionMatches; }
}

NSInteger ZZObservedDetailLastStatus(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastStatusCode; }
}

NSString *ZZObservedDetailLastAllow(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastAllowHeader.copy ?: @""; }
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
    return ZZRequestValue(request, @[@"productId", @"productID", @"goodsId", @"itemId", @"infoId", @"strInfoId", @"item_id", @"goods_id", @"wareId", @"wareID", @"ware_id", @"auctionId", @"auctionID", @"spuId", @"spuID"]);
}

static NSString *ZZProductIDFromResponseURL(NSURL *url) {
    if (!url) return @"";
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in c.queryItems ?: @[]) {
        NSString *name = item.name.lowercaseString ?: @"";
        if ([name isEqualToString:@"productid"] || [name isEqualToString:@"goodsid"] ||
            [name isEqualToString:@"itemid"] || [name isEqualToString:@"infoid"] ||
            [name isEqualToString:@"strinfoid"] || [name isEqualToString:@"wareid"] ||
            [name isEqualToString:@"auctionid"] || [name isEqualToString:@"spuid"]) {
            if (item.value.length) return item.value;
        }
    }
    return @"";
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

static NSString *ZZStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value respondsToSelector:@selector(stringValue)]) return [[value stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return @"";
}

static void ZZCollectExplicitProductIDs(id obj, NSMutableSet<NSString *> *ids, NSUInteger depth) {
    if (depth > 14 || !obj || !ids) return;
    if ([obj isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)obj stringByRemovingPercentEncoding] ?: (NSString *)obj;
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:NULL];
            if (parsed) ZZCollectExplicitProductIDs(parsed, ids, depth + 1);
        }
        return;
    }
    if ([obj isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)obj) ZZCollectExplicitProductIDs(child, ids, depth + 1);
        return;
    }
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = (NSDictionary *)obj;
    for (NSString *key in @[@"productId", @"productID", @"goodsId", @"goodsID", @"itemId", @"itemID", @"listingId", @"listingID", @"strInfoId", @"infoId"]) {
        NSString *value = ZZStringValue(d[key]);
        if (value.length && value.length < 128) [ids addObject:value];
    }
    id map = d[@"itemId2AttrInfo"];
    if ([map isKindOfClass:NSDictionary.class]) {
        for (NSString *key in (NSDictionary *)map) {
            if (key.length && key.length < 128) [ids addObject:key];
        }
    }
    for (NSString *key in d) {
        id child = d[key];
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class] || [child isKindOfClass:NSString.class]) {
            ZZCollectExplicitProductIDs(child, ids, depth + 1);
        }
    }
}

static void ZZRecordCapturedEntry(NSDictionary *entry, NSString *pid) {
    if (!pid.length) return;
    NSMutableDictionary *copy = [entry mutableCopy] ?: [NSMutableDictionary dictionary];
    copy[@"productId"] = pid;
    [[ZZProductVisibility shared] recordEntries:@[copy.copy] forProductIDs:@[pid]];
    ZZEnsureDetailCaptureLock();
    @synchronized (gDetailCaptureLock) { gDetailCapturedEntries += 1; }
}

// v46: The real app response can place the product id and the system-version
// attribute in different branches. The old one-pass inherited-PID walk could
// therefore see iOS 26.6.1 but never associate it with the product. Do a bounded
// two-pass association: request PID first; otherwise use a unique explicit PID;
// for itemId2AttrInfo, use each map key as the PID for its own attribute object.
static NSUInteger ZZCaptureActualDetailResponse(id obj, NSString *requestPID, NSUInteger depth) {
    if (depth > 14 || !obj) return 0;
    NSUInteger captured = 0;

    if ([obj isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)obj stringByRemovingPercentEncoding] ?: (NSString *)obj;
        if (([text hasPrefix:@"{"] || [text hasPrefix:@"["]) && text.length > 2) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:NULL];
            if (parsed) return ZZCaptureActualDetailResponse(parsed, requestPID, depth + 1);
        }
        if (requestPID.length) {
            NSString *version = ZZProductVersionFromObject(text);
            if (version.length) {
                ZZRecordCapturedEntry(@{ @"detailText": text, @"zzSystemVersion": version }, requestPID);
                return 1;
            }
        }
        return 0;
    }

    if ([obj isKindOfClass:NSArray.class]) {
        // Prefer item-level objects. A request PID, when present, is safe to
        // reuse across sibling branches of the same detail response.
        for (id child in (NSArray *)obj) captured += ZZCaptureActualDetailResponse(child, requestPID, depth + 1);
        return captured;
    }
    if (![obj isKindOfClass:NSDictionary.class]) return 0;

    NSDictionary *d = (NSDictionary *)obj;
    id map = d[@"itemId2AttrInfo"];
    if ([map isKindOfClass:NSDictionary.class]) {
        for (NSString *mapPID in (NSDictionary *)map) {
            id attrs = ((NSDictionary *)map)[mapPID];
            NSString *version = ZZProductVersionFromObject(attrs);
            if (version.length && mapPID.length) {
                ZZRecordCapturedEntry(@{ @"detail": attrs ?: @{}, @"zzSystemVersion": version }, mapPID);
                captured += 1;
            }
            captured += ZZCaptureActualDetailResponse(attrs, mapPID, depth + 1);
        }
    }

    NSString *localVersion = ZZProductVersionFromDictionary(d);
    if (localVersion.length) {
        NSString *pid = requestPID;
        if (!pid.length) {
            NSMutableSet<NSString *> *localIDs = [NSMutableSet set];
            ZZCollectExplicitProductIDs(d, localIDs, depth + 1);
            if (localIDs.count == 1) pid = localIDs.anyObject;
        }
        if (pid.length) {
            ZZRecordCapturedEntry(d, pid);
            captured += 1;
        }
    }

    // If this dictionary itself did not contain enough identity information,
    // descend into known response wrappers. The depth bound prevents the old
    // global-runtime-scan performance problem.
    for (NSString *key in @[@"respData", @"report", @"params", @"data", @"result", @"detail", @"detailInfo", @"detailData", @"attributes", @"attrs", @"attributeList", @"attrList", @"content"]) {
        id child = d[key];
        if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class] || [child isKindOfClass:NSString.class]) {
            captured += ZZCaptureActualDetailResponse(child, requestPID, depth + 1);
        }
    }
    return captured;
}


static void ZZObserveDetailResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    NSString *allow = @"";
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        NSDictionary *headers = ((NSHTTPURLResponse *)response).allHeaderFields;
        allow = headers[@"Allow"] ?: headers[@"allow"] ?: @"";
    }
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        gObservedDetailResponses += 1;
        gObservedDetailLastStatusCode = status;
        gObservedDetailLastAllowHeader = allow.copy ?: @"";
        if (status >= 200 && status < 300) gObservedDetail2xxResponses += 1;
    }

    NSString *preview = @"";
    if (data.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        if (text.length > 240) text = [text substringToIndex:240];
        preview = text ?: @"";
    }
    ZZFilterDebugWrite(@"[ZZDetailObserver] actual-response method=%@ status=%ld allow=%@ bytes=%lu pid=%@ body=%@ url=%@ error=%@",
                       request.HTTPMethod ?: @"GET", (long)status, allow,
                       (unsigned long)data.length, ZZProductIDFromRequest(request), preview,
                       request.URL.absoluteString ?: @"", error.localizedDescription ?: @"none");

    if (error || !data.length || status < 200 || status >= 300) return;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    if (!obj) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length) {
            NSString *direct = ZZProductVersionFromDictionary(@{ @"content": text });
            if (direct.length) {
                NSString *pid = ZZProductIDFromRequest(request);
                if (pid.length) {
                    NSDictionary *entry = @{ @"productId": pid, @"detailText": text, @"zzSystemVersion": direct };
                    [[ZZProductVisibility shared] recordEntries:@[entry] forProductIDs:@[pid]];
                    ZZEnsureDetailCaptureLock();
                    @synchronized (gDetailCaptureLock) { gDetailCapturedEntries += 1; }
                }
            }
        }
        return;
    }
    NSUInteger before = ZZDetailCapturedEntries();
    NSString *requestPID = ZZProductIDFromRequest(request);
    if (!requestPID.length) requestPID = ZZProductIDFromResponseURL(response.URL);

    // v47: perform a whole-response identity/version pass before the structural
    // association. This covers payloads where the ID and "iOS 18.7.7" live in
    // sibling branches rather than the same dictionary.
    NSMutableSet<NSString *> *candidateIDs = [NSMutableSet set];
    ZZCollectExplicitProductIDs(obj, candidateIDs, 0);
    NSString *wholeResponseVersion = ZZProductVersionFromObject(obj);
    if (!wholeResponseVersion.length) {
        NSData *flat = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
        NSString *flatText = flat.length ? [[NSString alloc] initWithData:flat encoding:NSUTF8StringEncoding] : @"";
        wholeResponseVersion = ZZExtractVersionFromText(flatText);
    }
    if (wholeResponseVersion.length) {
        ZZEnsureObservedRequestLock();
        @synchronized (gObservedRequestLock) { gObservedDetailVersionMatches += 1; }
    }

    NSUInteger captured = ZZCaptureActualDetailResponse(obj, requestPID, 0);
    NSUInteger after = ZZDetailCapturedEntries();

    // If there is exactly one explicit product identity in the whole response,
    // it is safe to bind the response-level system version to that product.
    if (captured == 0 && wholeResponseVersion.length && !requestPID.length && candidateIDs.count == 1) {
        NSString *pid = candidateIDs.anyObject;
        ZZRecordCapturedEntry(@{ @"detail": obj, @"zzSystemVersion": wholeResponseVersion }, pid);
        captured = 1;
        after = ZZDetailCapturedEntries();
    }

    if (captured == 0) {
        ZZFilterDebugWrite(@"[ZZDetailObserver] unlinked version=%@ requestPID=%@ candidateIDs=%lu urlPID=%@",
                           wholeResponseVersion ?: @"", requestPID ?: @"", (unsigned long)candidateIDs.count,
                           ZZProductIDFromResponseURL(response.URL) ?: @"");
    } else {
        ZZFilterDebugWrite(@"[ZZDetailObserver] version=%@ requestPID=%@ candidateIDs=%lu captured=%lu",
                           wholeResponseVersion ?: @"", requestPID ?: @"", (unsigned long)candidateIDs.count,
                           (unsigned long)(after-before));
    }
    if (after > before) ZZFilterDebugWrite(@"[ZZDetailObserver] captured=%lu method=%@ status=%ld pid=%@ url=%@", (unsigned long)(after-before), request.HTTPMethod ?: @"GET", (long)status, ZZProductIDFromRequest(request), request.URL.absoluteString ?: @"");
}


static void ZZStartObserverForRequest(NSURLRequest *request) {
    if (!request || gZZInsideObserverRequest || !ZZLooksLikeDetailRequest(request)) return;
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        if (gObservedDetailRequests >= 24) return;
        gObservedDetailRequests += 1;
    }
    NSMutableURLRequest *copyMutable = [request mutableCopy];
    [copyMutable setValue:@"1" forHTTPHeaderField:@"X-ZZFilter-Observer"];
    NSURLRequest *copy = copyMutable.copy;
    NSURLSession *observer = ZZObserverSession();
    BOOL previousGuard = gZZInsideObserverRequest;
    gZZInsideObserverRequest = YES;
    NSURLSessionDataTask *observerTask = [observer zz_filter_dataTaskWithRequest_completion:copy completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        ZZObserveDetailResponse(copy, data, response, error);
    }];
    gZZInsideObserverRequest = previousGuard;
    if (observerTask) {
        objc_setAssociatedObject(observerTask, kZZObserverTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [observerTask resume];
    }
}

static BOOL ZZTaskWasObserved(NSURLSessionDataTask *task) {
    return objc_getAssociatedObject(task, kZZObservedTaskKey) != nil;
}

static void ZZMarkTaskObserved(NSURLSessionDataTask *task) {
    if (task) objc_setAssociatedObject(task, kZZObservedTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL ZZIsObserverTask(NSURLSessionTask *task) {
    return task && objc_getAssociatedObject(task, kZZObserverTaskKey) != nil;
}

static void ZZInspectTaskForDetail(NSURLSessionDataTask *task) {
    if (!task || ZZIsObserverTask(task) || ZZTaskWasObserved(task)) return;
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if (!request || !ZZLooksLikeDetailRequest(request)) return;
    ZZMarkTaskObserved(task);
    ZZFilterDebugWrite(@"[ZZDetailObserver] task-created method=%@ url=%@ pid=%@", request.HTTPMethod ?: @"GET", request.URL.absoluteString ?: @"", ZZProductIDFromRequest(request));
    ZZStartObserverForRequest(request);
}


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
    (void)_cmd;
    if (!request) return [(NSURLSession *)self zz_filter_dataTaskWithRequest_completion:request completionHandler:completion];

    BOOL isDetail = ZZLooksLikeDetailRequest(request);
    BOOL isInternalObserver = [[request valueForHTTPHeaderField:@"X-ZZFilter-Observer"] isEqualToString:@"1"];
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = completion;
    if (isDetail && !isInternalObserver) {
        void (^originalCompletion)(NSData *, NSURLResponse *, NSError *) = [completion copy];
        NSURLRequest *observedRequest = request.copy;
        wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            ZZObserveDetailResponse(observedRequest, data, response, error);
            if (originalCompletion) originalCompletion(data, response, error);
        };
    }
    NSURLSessionDataTask *task = [(NSURLSession *)self zz_filter_dataTaskWithRequest_completion:request completionHandler:wrappedCompletion];
    if (!gZZInsideObserverRequest && isDetail) ZZStartObserverForRequest(request);
    return task;
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    (void)_cmd;
    if (!request) return [(NSURLSession *)self zz_filter_dataTaskWithRequest:request];
    NSURLSessionDataTask *task = [(NSURLSession *)self zz_filter_dataTaskWithRequest:request];
    if (!gZZInsideObserverRequest && ZZLooksLikeDetailRequest(request)) ZZStartObserverForRequest(request);
    return task;
}


@implementation NSURLSessionTask (ZZFilterResumeObserve)
- (void)zz_filter_resume {
    BOOL isObserver = ZZIsObserverTask(self);
    [self zz_filter_resume];
    if (!isObserver && [self isKindOfClass:NSURLSessionDataTask.class]) {
        ZZInspectTaskForDetail((NSURLSessionDataTask *)self);
    }
}
@end


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
        Method replacementCompletion = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithRequest_completion:completionHandler:));
        if (dataTaskWithCompletion && replacementCompletion) {
            method_exchangeImplementations(dataTaskWithCompletion, replacementCompletion);
        }
        Class taskCls = [NSURLSessionTask class];
        Method originalResume = class_getInstanceMethod(taskCls, @selector(resume));
        Method replacementResume = class_getInstanceMethod(taskCls, @selector(zz_filter_resume));
        if (originalResume && replacementResume) method_exchangeImplementations(originalResume, replacementResume);

        Method dataTaskSimple = class_getInstanceMethod(sessionCls, @selector(dataTaskWithRequest:));
        Method replacementSimple = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithRequest:));
        if (dataTaskSimple && replacementSimple) {
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
