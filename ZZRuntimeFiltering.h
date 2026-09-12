#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs non-invasive runtime adapters for listing classes when their
/// known model-array entry points are present. The adapter is independent of
/// the reference binary and only filters object arrays passed to those APIs.
FOUNDATION_EXPORT void ZZInstallRuntimeFiltering(void);

NS_ASSUME_NONNULL_END
