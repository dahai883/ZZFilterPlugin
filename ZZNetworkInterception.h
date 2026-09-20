#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void ZZInstallNetworkInterception(void);

/// Returns the cookie storages observed from the host app's NSURLSession
/// configurations. The reference implementation keeps these because the
/// default shared store is not always the store that owns the app session.
FOUNDATION_EXPORT NSArray<NSHTTPCookieStorage *> *ZZRegisteredCookieStorages(void);
FOUNDATION_EXPORT void ZZRegisterCookieStorage(NSHTTPCookieStorage * _Nullable storage);
FOUNDATION_EXPORT NSArray<NSHTTPCookie *> *ZZCookiesForURL(NSURL * _Nullable url);
FOUNDATION_EXPORT void ZZStoreResponseCookies(NSHTTPURLResponse * _Nullable response, NSURL * _Nullable url);
FOUNDATION_EXPORT NSUInteger ZZDetailCapturedEntries(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailRequests(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailResponses(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetail2xxResponses(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailAny2xxResponses(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastObserved2xxURL(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastObserved2xxMethod(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastObserved2xxBody(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastObserved2xxContentType(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailLastObserved2xxBytes(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailVersionMatches(void);
FOUNDATION_EXPORT NSInteger ZZObservedDetailLastStatus(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastAllow(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxVersion(void);
FOUNDATION_EXPORT NSUInteger ZZObservedDetailLast2xxBytes(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxContentType(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxURL(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxBody(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureURL(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureMethod(void);
FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureBody(void);

NS_ASSUME_NONNULL_END
