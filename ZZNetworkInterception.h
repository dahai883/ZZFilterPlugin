#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs the plugin's NSURLProtocol into the standard NSURLSession
/// configurations used by an authorized host application.
FOUNDATION_EXPORT void ZZInstallNetworkInterception(void);

NS_ASSUME_NONNULL_END
