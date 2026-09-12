#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void ZZInstallRuntimeFiltering(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringHookCount(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringCalls(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringScannedClasses(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringMatchedClasses(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringMatchedMethods(void);
FOUNDATION_EXPORT NSUInteger ZZRuntimeFilteringHookFailures(void);
FOUNDATION_EXPORT NSString *ZZRuntimeFilteringLastSummary(void);

NS_ASSUME_NONNULL_END
