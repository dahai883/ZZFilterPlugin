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

NS_ASSUME_NONNULL_END
