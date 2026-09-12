#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns YES when the built-in filter self-test passes.
FOUNDATION_EXPORT BOOL ZZFilterDebugSelfTest(void);

/// Emits a short build/runtime diagnostic line through os_log.
FOUNDATION_EXPORT void ZZFilterDebugLogBuildInfo(void);
FOUNDATION_EXPORT void ZZFilterDiagnosticLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT NSString *ZZFilterDiagnosticLogPath(void);
FOUNDATION_EXPORT void ZZFilterDiagnosticLogReset(void);

NS_ASSUME_NONNULL_END
