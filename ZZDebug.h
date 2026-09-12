#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL ZZFilterDebugSelfTest(void);
FOUNDATION_EXPORT void ZZFilterDebugLogBuildInfo(void);
FOUNDATION_EXPORT void ZZDiagLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT NSString *ZZDiagLogPath(void);

NS_ASSUME_NONNULL_END
