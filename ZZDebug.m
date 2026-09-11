#import <Foundation/Foundation.h>
#import <os/log.h>
#import <TargetConditionals.h>
#import "ZZDebug.h"

static os_log_t ZZDebugLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.zzfilterplugin", "debug");
    });
    return log;
}

void ZZFilterDebugLogBuildInfo(void) {
#if defined(__arm64e__)
    const char *arch = "arm64e";
#elif defined(__arm64__)
    const char *arch = "arm64";
#else
    const char *arch = "unknown";
#endif
    os_log(ZZDebugLog(), "ZZFilterPlugin DEBUG build; arch=%{public}s; iOS min=16.0", arch);
}
