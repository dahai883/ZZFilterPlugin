#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs non-invasive runtime adapters for listing classes when their
/// known model-array entry points are present. The adapter is independent of
/// the reference binary and only filters object arrays passed to those APIs.
FOUNDATION_EXPORT void ZZInstallRuntimeFiltering(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringHookCount(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringCalls(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringClassesScanned(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringSelectorMatches(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringHookFailures(void);
FOUNDATION_EXPORT NSString *ZZRuntimeFilteringLastDiscovery(void);

NS_ASSUME_NONNULL_END
