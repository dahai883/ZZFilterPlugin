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
static NSUInteger gObservedDetailAny2xxResponses;
static NSUInteger gObservedDetailVersionMatches;
static NSInteger gObservedDetailLastStatusCode;
static NSString *gObservedDetailLastAllowHeader;
static NSString *gObservedDetailLast2xxVersion;
static NSUInteger gObservedDetailLast2xxBytes;
static NSString *gObservedDetailLast2xxContentType;
static NSString *gObservedDetailLast2xxURL;
static NSString *gObservedDetailLast2xxBody;
static NSString *gObservedDetailLastObserved2xxURL;
static NSString *gObservedDetailLastObserved2xxMethod;
static NSString *gObservedDetailLastObserved2xxBody;
static NSString *gObservedDetailLastObserved2xxContentType;
static NSUInteger gObservedDetailLastObserved2xxBytes;
static NSString *gObservedDetailLastFailureURL;
static NSString *gObservedDetailLastFailureMethod;
static NSString *gObservedDetailLastFailureBody;
static NSString *gObservedDetailLastRequestURL;
static NSString *gObservedDetailLastRequestMethod;
static NSString *gObservedDetailLastRequestBody;
static NSUInteger gProtocolDetailRequests;
static NSUInteger gProtocolDetailResponses;
static NSUInteger gProtocolDetail2xxResponses;
static NSUInteger gProtocolDetailFailureResponses;
static NSInteger gProtocolDetailLastStatusCode;
static NSString *gProtocolDetailLastURL;
static NSString *gProtocolDetailLastMethod;
static NSString *gProtocolDetailLastBody;
static NSUInteger gObservedNetworkTaskRequests;
static NSString *gObservedNetworkTaskLastURL;
static NSString *gObservedNetworkTaskLastMethod;
static NSString *gObservedNetworkTaskLastBody;
static NSUInteger gObservedNetworkTaskCandidateRequests;
static NSString *gObservedNetworkTaskCandidateURL;
static NSString *gObservedNetworkTaskCandidateMethod;
static NSString *gObservedNetworkTaskCandidateBody;
static NSUInteger gObservedNetworkPayloadResponses;
static NSUInteger gObservedNetworkVersionPayloads;
static NSInteger gObservedNetworkLastPayloadStatusCode;
static NSString *gObservedNetworkLastPayloadURL;
static NSString *gObservedNetworkLastPayloadMethod;
static NSString *gObservedNetworkLastPayloadBody;
static NSString *gObservedNetworkLastPayloadVersion;
static NSObject *gDetailCaptureLock;
static NSObject *gObservedRequestLock;
static __thread BOOL gZZInsideObserverRequest = NO;
static const void *kZZObservedTaskKey = &kZZObservedTaskKey;

static void ZZEnsureDetailCaptureLock(void);
static BOOL ZZIsZhuanzhuanNetworkURL(NSURL *url);
static void ZZEnsureObservedRequestLock(void);
static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *));
static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request);
static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL(id self, SEL _cmd, NSURL *url);
static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL_completion(id self, SEL _cmd, NSURL *url, void (^completion)(NSData *, NSURLResponse *, NSError *));
static NSString *ZZExtractVersionFromFlatText(NSString *value);
static void ZZRecordObservedDetailRequest(NSURLRequest *request);
static NSUInteger ZZCaptureActualDetailResponse(id obj, NSString *requestPID, NSUInteger depth);
static BOOL ZZIsExcludedDetailResponseURL(NSURL *url);
static BOOL ZZLooksLikeDetailResponse(NSURLRequest *request, NSURLResponse *response, NSData *data);
static NSString *ZZProtocolBodyPreviewForDebug(NSData *data);
static void ZZRecordNetworkTaskResume(NSURLSessionTask *task);
static BOOL ZZLooksLikeTaskCandidate(NSURLRequest *request);
static void ZZObserveNetworkCompletionResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error);

// All private selectors/helpers are declared before first use.
@interface NSURLSession (ZZFilterObserveForward)
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest_completion:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL_completion:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
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

NSUInteger ZZObservedDetailAny2xxResponses(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailAny2xxResponses; }
}

NSString *ZZObservedDetailLastRequestURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastRequestURL.copy ?: @""; }
}

NSString *ZZObservedDetailLastRequestMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastRequestMethod.copy ?: @""; }
}

NSString *ZZObservedDetailLastRequestBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastRequestBody.copy ?: @""; }
}

NSString *ZZObservedDetailLastObserved2xxURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastObserved2xxURL.copy ?: @""; }
}

NSString *ZZObservedDetailLastObserved2xxMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastObserved2xxMethod.copy ?: @""; }
}

NSString *ZZObservedDetailLastObserved2xxBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastObserved2xxBody.copy ?: @""; }
}

NSString *ZZObservedDetailLastObserved2xxContentType(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastObserved2xxContentType.copy ?: @""; }
}

NSUInteger ZZObservedDetailLastObserved2xxBytes(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastObserved2xxBytes; }
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

NSString *ZZObservedDetailLast2xxVersion(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLast2xxVersion.copy ?: @""; }
}

NSUInteger ZZObservedDetailLast2xxBytes(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLast2xxBytes; }
}

NSString *ZZObservedDetailLast2xxContentType(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLast2xxContentType.copy ?: @""; }
}

NSString *ZZObservedDetailLast2xxURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLast2xxURL.copy ?: @""; }
}

NSString *ZZObservedDetailLast2xxBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLast2xxBody.copy ?: @""; }
}

NSString *ZZObservedDetailLastFailureURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastFailureURL.copy ?: @""; }
}

NSString *ZZObservedDetailLastFailureMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastFailureMethod.copy ?: @""; }
}

NSString *ZZObservedDetailLastFailureBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedDetailLastFailureBody.copy ?: @""; }
}

static NSString *ZZExtractVersionFromFlatText(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return @"";

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"(?i)\\b(?:ios|iphone\\s*os|ipad\\s*os)\\s*(?:版本|version)?\\s*[:：-]?\\s*(\\d{1,3}(?:\\.\\d{1,3}){0,2})\\b"
        options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (m) {
        NSRange r = [m rangeAtIndex:1];
        if (r.location != NSNotFound) return [value substringWithRange:r];
    }

    re = [NSRegularExpression regularExpressionWithPattern:
        @"(?:系统版本(?:号)?|系统\\s*版本|OS版本|iOS\\s*版本(?:号)?|system\\s*version)\\s*[:：=]?\\s*(?:iOS\\s*)?(\\d{1,3}(?:\\.\\d{1,3}){0,2})"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    m = [re firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (m) {
        NSRange r = [m rangeAtIndex:1];
        if (r.location != NSNotFound) return [value substringWithRange:r];
    }
    return @"";
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

static BOOL ZZIsInternalDetailRequest(NSURLRequest *request) {
    return [[request valueForHTTPHeaderField:@"X-ZZFilter-Internal-Detail"] isEqualToString:@"1"];
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


static NSString *ZZExtractVersionFromRawResponseData(NSData *data) {
    if (!data.length) return @"";
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (utf8.length) [texts addObject:utf8];
    NSString *utf16 = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
    if (utf16.length) [texts addObject:utf16];
    NSString *utf16be = [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
    if (utf16be.length) [texts addObject:utf16be];
    for (NSString *text in texts) {
        NSString *v = ZZExtractVersionFromFlatText(text);
        if (v.length) return v;
        NSRegularExpression *keyRe = [NSRegularExpression regularExpressionWithPattern:
            @"(?i)(?:systemVersion|system_version|iosVersion|ios_version|iphoneOSVersion|osVersion|\\\"ios\\\"|\\\"systemVersion\\\")[^0-9]{0,100}(\\d{1,3}(?:\\.\\d{1,3}){0,2})"
            options:0 error:NULL];
        NSTextCheckingResult *m = [keyRe firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (m) {
            NSRange r = [m rangeAtIndex:1];
            if (r.location != NSNotFound) return [text substringWithRange:r];
        }
    }
    return @"";
}

static BOOL ZZIsExcludedDetailResponseURL(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    NSString *absolute = url.absoluteString.lowercaseString ?: @"";
    return [path containsString:@"coke-real"] || [absolute containsString:@"/v1/coke-real"];
}

static BOOL ZZLooksLikeDetailResponse(NSURLRequest *request, NSURLResponse *response, NSData *data) {
    NSURL *url = response.URL ?: request.URL;
    if (!url || ZZIsExcludedDetailResponseURL(url)) return NO;

    // A response from an explicit detail/moreinfo endpoint is a candidate even
    // when the payload does not expose the iOS value at the top level.
    NSString *path = url.path.lowercaseString ?: @"";
    NSString *requestPath = request.URL.path.lowercaseString ?: @"";
    BOOL detailPath = [path containsString:@"detail"] ||
                      [path containsString:@"moreinfo"] ||
                      [path containsString:@"waresshow"] ||
                      [path containsString:@"goods"] ||
                      [path containsString:@"item"] ||
                      [requestPath containsString:@"detail"] ||
                      [requestPath containsString:@"moreinfo"] ||
                      [requestPath containsString:@"waresshow"] ||
                      [requestPath containsString:@"goods"] ||
                      [requestPath containsString:@"item"];

    if (data.length) {
        id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
        if (obj && ZZProductVersionFromObject(obj).length) return YES;

        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        if (text.length && ZZExtractVersionFromFlatText(text).length) return YES;
        if (text.length) {
            NSString *lower = text.lowercaseString;
            if ([lower containsString:@"系统版本"] || [lower containsString:@"systemversion"] ||
                [lower containsString:@"iosversion"] || [lower containsString:@"iphoneosversion"]) {
                return YES;
            }
        }
    }
    return detailPath;
}

static void ZZObserveNetworkCompletionResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error) {
    if (!request || !request.URL || ZZIsInternalDetailRequest(request)) return;
    if (!ZZIsZhuanzhuanNetworkURL(request.URL)) return;
    if (ZZIsExcludedDetailResponseURL(response.URL ?: request.URL)) return;

    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    NSString *url = response.URL.absoluteString ?: request.URL.absoluteString ?: @"";
    NSString *method = request.HTTPMethod ?: @"GET";
    NSString *preview = ZZProtocolBodyPreviewForDebug(data);
    // Keep the generic census bounded: only inspect reasonably small completion
    // payloads. This is passive and does not alter the response delivered to the app.
    if (data.length > (1024 * 1024)) return;

    NSString *version = ZZExtractVersionFromRawResponseData(data);
    BOOL hasVersion = version.length > 0;
    BOOL candidate = ZZLooksLikeTaskCandidate(request);
    if (!candidate && !hasVersion) return;

    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        gObservedNetworkPayloadResponses += 1;
        gObservedNetworkLastPayloadStatusCode = status;
        gObservedNetworkLastPayloadURL = url.copy;
        gObservedNetworkLastPayloadMethod = method.copy;
        gObservedNetworkLastPayloadBody = preview.copy ?: @"";
        gObservedNetworkLastPayloadVersion = version.copy ?: @"";
        if (hasVersion) gObservedNetworkVersionPayloads += 1;
    }

    ZZFilterDebugWrite(@"[ZZPayloadCensus] response method=%@ status=%ld candidate=%@ version=%@ bytes=%lu url=%@ body=%@ error=%@",
                       method, (long)status, candidate ? @"YES" : @"NO", version ?: @"",
                       (unsigned long)data.length, url, preview, error.localizedDescription ?: @"none");

    if (status < 200 || status >= 300 || !hasVersion) return;

    NSString *pid = ZZProductIDFromRequest(request);
    if (!pid.length) pid = ZZProductIDFromResponseURL(response.URL);

    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    if (obj) {
        NSUInteger before = ZZDetailCapturedEntries();
        NSUInteger captured = ZZCaptureActualDetailResponse(obj, pid, 0);
        if (captured == 0 && pid.length) {
            ZZRecordCapturedEntry(@{ @"detail": obj, @"zzSystemVersion": version }, pid);
            captured = 1;
        }
        if (captured || before != ZZDetailCapturedEntries()) {
            ZZFilterDebugWrite(@"[ZZPayloadCensus] version-capture version=%@ pid=%@ captured=%lu url=%@",
                               version, pid ?: @"", (unsigned long)(ZZDetailCapturedEntries() - before), url);
        }
    } else if (pid.length) {
        ZZRecordCapturedEntry(@{ @"detailText": preview ?: @"", @"zzSystemVersion": version }, pid);
    }
}

static void ZZRecordObservedDetailRequest(NSURLRequest *request) {
    if (!request || !request.URL || gZZInsideObserverRequest || ZZIsInternalDetailRequest(request)) return;
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        if (gObservedDetailRequests >= 48) return;
        gObservedDetailRequests += 1;
        gObservedDetailLastRequestURL = (request.URL.absoluteString ?: @"").copy;
        gObservedDetailLastRequestMethod = (request.HTTPMethod ?: @"GET").copy;
        gObservedDetailLastRequestBody = ZZProtocolBodyPreviewForDebug(request.HTTPBody).copy;
    }
    ZZFilterDebugWrite(@"[ZZDetailObserver] observe-request method=%@ url=%@ pid=%@ body=%@",
                       request.HTTPMethod ?: @"GET",
                       request.URL.absoluteString ?: @"",
                       ZZProductIDFromRequest(request) ?: @"",
                       ZZProtocolBodyPreviewForDebug(request.HTTPBody));
}

static void ZZObserveDetailResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error) {
    if (ZZIsInternalDetailRequest(request)) return;
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    NSString *allow = @"";
    NSString *contentType = @"";
    if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        NSDictionary *headers = ((NSHTTPURLResponse *)response).allHeaderFields;
        allow = headers[@"Allow"] ?: headers[@"allow"] ?: @"";
        id ct = headers[@"Content-Type"] ?: headers[@"content-type"];
        if ([ct isKindOfClass:NSString.class]) contentType = ct;
    }

    NSString *preview = @"";
    if (data.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        if (text.length > 420) text = [text substringToIndex:420];
        preview = text ?: @"";
    }

    BOOL candidate2xx = (status >= 200 && status < 300) &&
                       ZZLooksLikeDetailResponse(request, response, data);
    NSString *raw2xxVersion = candidate2xx ? ZZExtractVersionFromRawResponseData(data) : @"";

    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        gObservedDetailResponses += 1;
        gObservedDetailLastStatusCode = status;
        gObservedDetailLastAllowHeader = allow.copy ?: @"";

        // v57: keep the last *any* observed 2xx separately from the stricter
        // detail candidate counter. This tells us exactly what the app itself
        // returned even when the payload does not yet expose an iOS version.
        if (status >= 200 && status < 300) {
            gObservedDetailAny2xxResponses += 1;
            gObservedDetailLastObserved2xxURL = (response.URL.absoluteString ?: request.URL.absoluteString ?: @"").copy;
            gObservedDetailLastObserved2xxMethod = (request.HTTPMethod ?: @"GET").copy;
            gObservedDetailLastObserved2xxBody = preview.copy ?: @"";
            gObservedDetailLastObserved2xxContentType = contentType.copy ?: @"";
            gObservedDetailLastObserved2xxBytes = data.length;
        }

        if (status >= 400 && status < 600) {
            gObservedDetailLastFailureURL = (response.URL.absoluteString ?: request.URL.absoluteString ?: @"").copy;
            gObservedDetailLastFailureMethod = (request.HTTPMethod ?: @"GET").copy;
            gObservedDetailLastFailureBody = preview.copy ?: @"";
        }

        if (candidate2xx) {
            gObservedDetail2xxResponses += 1;
            gObservedDetailLast2xxVersion = raw2xxVersion.copy ?: @"";
            gObservedDetailLast2xxBytes = data.length;
            gObservedDetailLast2xxContentType = contentType.copy ?: @"";
            gObservedDetailLast2xxURL = response.URL.absoluteString.copy ?: request.URL.absoluteString.copy ?: @"";
            gObservedDetailLast2xxBody = preview.copy ?: @"";
            if (raw2xxVersion.length) gObservedDetailVersionMatches += 1;
        }
    }

    ZZFilterDebugWrite(@"[ZZDetailObserver] actual-response method=%@ status=%ld candidate2xx=%@ any2xx=%@ allow=%@ bytes=%lu pid=%@ body=%@ url=%@ error=%@",
                       request.HTTPMethod ?: @"GET", (long)status, candidate2xx ? @"YES" : @"NO",
                       (status >= 200 && status < 300) ? @"YES" : @"NO", allow,
                       (unsigned long)data.length, ZZProductIDFromRequest(request), preview,
                       request.URL.absoluteString ?: @"", error.localizedDescription ?: @"none");

    if (error || !data.length || status < 200 || status >= 300 || !candidate2xx) return;

    NSString *requestPIDForRaw = ZZProductIDFromRequest(request);
    if (!requestPIDForRaw.length) requestPIDForRaw = ZZProductIDFromResponseURL(response.URL);
    if (raw2xxVersion.length && requestPIDForRaw.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        ZZRecordCapturedEntry(@{ @"detailText": text, @"zzSystemVersion": raw2xxVersion }, requestPIDForRaw);
    }

    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    if (!obj) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length) {
            NSString *direct = ZZProductVersionFromDictionary(@{ @"content": text });
            if (direct.length && requestPIDForRaw.length) {
                ZZRecordCapturedEntry(@{ @"productId": requestPIDForRaw, @"detailText": text, @"zzSystemVersion": direct }, requestPIDForRaw);
            }
        }
        return;
    }

    NSUInteger before = ZZDetailCapturedEntries();
    NSString *requestPID = requestPIDForRaw;

    NSMutableSet<NSString *> *candidateIDs = [NSMutableSet set];
    ZZCollectExplicitProductIDs(obj, candidateIDs, 0);
    NSString *wholeResponseVersion = ZZProductVersionFromObject(obj);
    if (!wholeResponseVersion.length) {
        NSData *flat = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
        NSString *flatText = flat.length ? [[NSString alloc] initWithData:flat encoding:NSUTF8StringEncoding] : @"";
        wholeResponseVersion = ZZExtractVersionFromFlatText(flatText);
    }

    NSUInteger captured = ZZCaptureActualDetailResponse(obj, requestPID, 0);
    NSUInteger after = ZZDetailCapturedEntries();

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
    if (after > before) {
        ZZFilterDebugWrite(@"[ZZDetailObserver] captured=%lu method=%@ status=%ld pid=%@ url=%@",
                           (unsigned long)(after-before), request.HTTPMethod ?: @"GET",
                           (long)status, ZZProductIDFromRequest(request),
                           request.URL.absoluteString ?: @"");
    }
}

static BOOL ZZIsZhuanzhuanNetworkURL(NSURL *url) {
    NSString *host = url.host.lowercaseString ?: @"";
    return [host hasSuffix:@"zhuanzhuan.com"] || [host hasSuffix:@"zhuanzhuan.com.cn"];
}

static void ZZRecordNetworkTaskResume(NSURLSessionTask *task) {
    if (!task) return;
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if (!request || !request.URL || !ZZIsZhuanzhuanNetworkURL(request.URL)) return;
    if (ZZIsInternalDetailRequest(request)) return;

    NSString *url = request.URL.absoluteString ?: @"";
    NSString *path = request.URL.path.lowercaseString ?: @"";
    // Keep this census passive and lightweight. It is intentionally broader
    // than ZZLooksLikeDetailRequest so an opaque endpoint can be discovered.
    // Known non-detail health/telemetry traffic is still recorded in the log,
    // but the popup prefers the latest request whose path is not coke-real.
    NSString *bodyPreview = ZZProtocolBodyPreviewForDebug(request.HTTPBody).copy ?: @"";
    NSString *method = (request.HTTPMethod ?: @"GET").copy;
    BOOL candidate = ZZLooksLikeTaskCandidate(request);
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        gObservedNetworkTaskRequests += 1;
        gObservedNetworkTaskLastURL = url.copy;
        gObservedNetworkTaskLastMethod = method;
        gObservedNetworkTaskLastBody = bodyPreview;
        if (candidate) {
            gObservedNetworkTaskCandidateRequests += 1;
            gObservedNetworkTaskCandidateURL = url.copy;
            gObservedNetworkTaskCandidateMethod = method;
            gObservedNetworkTaskCandidateBody = bodyPreview;
        }
    }
    ZZFilterDebugWrite(@"[ZZTaskCensus] resume method=%@ candidate=%@ path=%@ url=%@ body=%@",
                       method, candidate ? @"YES" : @"NO", path, url, bodyPreview);
}

static BOOL ZZLooksLikeTaskCandidate(NSURLRequest *request) {
    if (!request || !request.URL || ZZIsInternalDetailRequest(request)) return NO;
    NSURL *url = request.URL;
    if (ZZIsExcludedDetailResponseURL(url)) return NO;
    NSString *path = url.path.lowercaseString ?: @"";
    NSString *absolute = url.absoluteString.lowercaseString ?: @"";
    NSString *body = ZZProtocolBodyPreviewForDebug(request.HTTPBody).lowercaseString ?: @"";
    if ([path containsString:@"detail"] || [path containsString:@"goods"] ||
        [path containsString:@"product"] || [path containsString:@"item"] ||
        [path containsString:@"streamline"]) return YES;
    if ([absolute containsString:@"productid="] || [absolute containsString:@"goodsid="] ||
        [absolute containsString:@"itemid="] || [body containsString:@"productid"] ||
        [body containsString:@"goodsid"] || [body containsString:@"itemid"]) return YES;
    return NO;
}

static BOOL ZZTaskWasObserved(NSURLSessionDataTask *task) {
    return objc_getAssociatedObject(task, kZZObservedTaskKey) != nil;
}

static void ZZMarkTaskObserved(NSURLSessionDataTask *task) {
    if (task) objc_setAssociatedObject(task, kZZObservedTaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ZZInspectTaskForDetail(NSURLSessionDataTask *task) {
    if (!task || ZZTaskWasObserved(task)) return;
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if (!request || ZZIsInternalDetailRequest(request) || !ZZLooksLikeDetailRequest(request)) return;
    ZZMarkTaskObserved(task);
    ZZRecordObservedDetailRequest(request);
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    (void)_cmd;
    if (!request) return [(NSURLSession *)self zz_filter_dataTaskWithRequest_completion:request completionHandler:completion];

    BOOL isDetail = !ZZIsInternalDetailRequest(request) && ZZLooksLikeDetailRequest(request);
    BOOL isZhuanzhuan = !ZZIsInternalDetailRequest(request) && ZZIsZhuanzhuanNetworkURL(request.URL);
    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = completion;
    if ((isDetail || isZhuanzhuan) && !gZZInsideObserverRequest) {
        void (^originalCompletion)(NSData *, NSURLResponse *, NSError *) = [completion copy];
        NSURLRequest *observedRequest = request.copy;
        wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            ZZObserveNetworkCompletionResponse(observedRequest, data, response, error);
            if (isDetail) ZZObserveDetailResponse(observedRequest, data, response, error);
            if (originalCompletion) originalCompletion(data, response, error);
        };
    }
    return [(NSURLSession *)self zz_filter_dataTaskWithRequest_completion:request completionHandler:wrappedCompletion];
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request) {
    (void)_cmd;
    if (!request) return [(NSURLSession *)self zz_filter_dataTaskWithRequest:request];
    return [(NSURLSession *)self zz_filter_dataTaskWithRequest:request];
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL_completion(id self, SEL _cmd, NSURL *url, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    (void)_cmd;
    if (!url) return [(NSURLSession *)self zz_filter_dataTaskWithURL_completion:url completionHandler:completion];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    BOOL isDetail = !ZZIsInternalDetailRequest(request) && ZZLooksLikeDetailRequest(request);
    BOOL isZhuanzhuan = !ZZIsInternalDetailRequest(request) && ZZIsZhuanzhuanNetworkURL(request.URL);
    if ((isDetail || isZhuanzhuan) && !gZZInsideObserverRequest) {
        void (^originalCompletion)(NSData *, NSURLResponse *, NSError *) = [completion copy];
        NSURLRequest *observedRequest = request.copy;
        completion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            ZZObserveNetworkCompletionResponse(observedRequest, data, response, error);
            if (isDetail) ZZObserveDetailResponse(observedRequest, data, response, error);
            if (originalCompletion) originalCompletion(data, response, error);
        };
    }
    return [(NSURLSession *)self zz_filter_dataTaskWithURL_completion:url completionHandler:completion];
}

static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL(id self, SEL _cmd, NSURL *url) {
    (void)_cmd;
    if (!url) return [(NSURLSession *)self zz_filter_dataTaskWithURL:url];
    return [(NSURLSession *)self zz_filter_dataTaskWithURL:url];
}

@implementation NSURLSessionTask (ZZFilterResumeObserve)
- (void)zz_filter_resume {
    ZZRecordNetworkTaskResume(self);
    [self zz_filter_resume];
    if ([self isKindOfClass:NSURLSessionDataTask.class]) {
        ZZInspectTaskForDetail((NSURLSessionDataTask *)self);
    }
}
@end


static NSString *ZZProtocolBodyPreviewForDebug(NSData *data) {
    if (!data.length) return @"";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (text.length > 420) text = [text substringToIndex:420];
    return text ?: @"";
}

NSUInteger ZZObservedNetworkTaskRequests(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskRequests; }
}

NSString *ZZObservedNetworkTaskLastURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskLastURL.copy ?: @""; }
}

NSString *ZZObservedNetworkTaskLastMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskLastMethod.copy ?: @""; }
}

NSString *ZZObservedNetworkTaskLastBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskLastBody.copy ?: @""; }
}

NSUInteger ZZObservedNetworkTaskCandidateRequests(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskCandidateRequests; }
}

NSString *ZZObservedNetworkTaskCandidateURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskCandidateURL.copy ?: @""; }
}

NSString *ZZObservedNetworkTaskCandidateMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskCandidateMethod.copy ?: @""; }
}

NSString *ZZObservedNetworkTaskCandidateBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkTaskCandidateBody.copy ?: @""; }
}

NSUInteger ZZObservedNetworkPayloadResponses(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkPayloadResponses; }
}

NSUInteger ZZObservedNetworkVersionPayloads(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkVersionPayloads; }
}

NSInteger ZZObservedNetworkLastPayloadStatus(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkLastPayloadStatusCode; }
}

NSString *ZZObservedNetworkLastPayloadURL(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkLastPayloadURL.copy ?: @""; }
}

NSString *ZZObservedNetworkLastPayloadMethod(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkLastPayloadMethod.copy ?: @""; }
}

NSString *ZZObservedNetworkLastPayloadBody(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkLastPayloadBody.copy ?: @""; }
}

NSString *ZZObservedNetworkLastPayloadVersion(void) {
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { return gObservedNetworkLastPayloadVersion.copy ?: @""; }
}

NSUInteger ZZProtocolDetailRequests(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailRequests; } }
NSUInteger ZZProtocolDetailResponses(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailResponses; } }
NSUInteger ZZProtocolDetail2xxResponses(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetail2xxResponses; } }
NSUInteger ZZProtocolDetailFailureResponses(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailFailureResponses; } }
NSInteger ZZProtocolDetailLastStatus(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailLastStatusCode; } }
NSString *ZZProtocolDetailLastURL(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailLastURL.copy ?: @""; } }
NSString *ZZProtocolDetailLastMethod(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailLastMethod.copy ?: @""; } }
NSString *ZZProtocolDetailLastBody(void) { ZZEnsureObservedRequestLock(); @synchronized (gObservedRequestLock) { return gProtocolDetailLastBody.copy ?: @""; } }

void ZZRecordProtocolDetailRequest(NSURLRequest *request) {
    if (!request) return;
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) { gProtocolDetailRequests += 1; }
    ZZFilterDebugWrite(@"[ZZProtocolDetail] request method=%@ url=%@ body=%@", request.HTTPMethod ?: @"GET", request.URL.absoluteString ?: @"", ZZProtocolBodyPreviewForDebug(request.HTTPBody));
}

void ZZRecordProtocolDetailResponse(NSURLRequest *request, NSURLResponse *response, NSData *data) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    NSString *url = response.URL.absoluteString ?: request.URL.absoluteString ?: @"";
    NSString *method = request.HTTPMethod ?: @"GET";
    NSString *body = ZZProtocolBodyPreviewForDebug(data);
    ZZEnsureObservedRequestLock();
    @synchronized (gObservedRequestLock) {
        gProtocolDetailResponses += 1;
        gProtocolDetailLastStatusCode = status;
        gProtocolDetailLastURL = url.copy;
        gProtocolDetailLastMethod = method.copy;
        gProtocolDetailLastBody = body.copy;
        if (status >= 200 && status < 300) gProtocolDetail2xxResponses += 1;
        else if (status >= 400 && status < 600) gProtocolDetailFailureResponses += 1;
    }
    ZZFilterDebugWrite(@"[ZZProtocolDetail] response method=%@ status=%ld bytes=%lu url=%@ body=%@", method, (long)status, (unsigned long)data.length, url, body);
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
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL:(NSURL *)url;
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL_completion:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

@implementation NSURLSession (ZZFilterObserve)
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest:(NSURLRequest *)request { return ZZ_filter_dataTaskWithRequest(self, _cmd, request); }
- (NSURLSessionDataTask *)zz_filter_dataTaskWithRequest_completion:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler { return ZZ_filter_dataTaskWithRequest_completion(self, _cmd, request, completionHandler); }
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL:(NSURL *)url { return ZZ_filter_dataTaskWithURL(self, _cmd, url); }
- (NSURLSessionDataTask *)zz_filter_dataTaskWithURL_completion:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler { return ZZ_filter_dataTaskWithURL_completion(self, _cmd, url, completionHandler); }
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

        Method dataTaskURLCompletion = class_getInstanceMethod(sessionCls, @selector(dataTaskWithURL:completionHandler:));
        Method replacementURLCompletion = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithURL_completion:completionHandler:));
        if (dataTaskURLCompletion && replacementURLCompletion) {
            method_exchangeImplementations(dataTaskURLCompletion, replacementURLCompletion);
        }

        Method dataTaskURLSimple = class_getInstanceMethod(sessionCls, @selector(dataTaskWithURL:));
        Method replacementURLSimple = class_getInstanceMethod(sessionCls, @selector(zz_filter_dataTaskWithURL:));
        if (dataTaskURLSimple && replacementURLSimple) {
            method_exchangeImplementations(dataTaskURLSimple, replacementURLSimple);
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
