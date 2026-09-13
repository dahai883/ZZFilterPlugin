#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs non-invasive runtime adapters for listing classes when their
/// known model-array entry points are present. The adapter is independent of
/// the reference binary and only filters object arrays passed to those APIs.
FOUNDATION_EXPORT void ZZInstallRuntimeFiltering(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringHookCount(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringCalls(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeCandidateCount(void);
FOUNDATION_EXPORT NSString *ZZRuntimeDiagnosticSummary(void);
FOUNDATION_EXPORT void ZZRequestAdditionalListingPages(id controller, NSUInteger count);

NS_ASSUME_NONNULL_END
