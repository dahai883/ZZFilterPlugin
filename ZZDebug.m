#import <Foundation/Foundation.h>
#import <os/log.h>
#import <TargetConditionals.h>
#import <unistd.h>
#import <stdarg.h>
#import <stdio.h>
#import <dlfcn.h>
#import "ZZDebug.h"

static os_log_t ZZDebugLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.zzfilterplugin", "debug");
    });
    return log;
}

void ZZFilterDebugFileLog(NSString *format, ...) {
    if (!format) return;
    NSString *line = nil;
    va_list args;
    va_start(args, format);
    line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!line) return;

    FILE *fp = fopen("/tmp/ZZFilterPlugin-diagnostic.log", "a");
    if (!fp) return;
    NSDate *now = [NSDate date];
    fprintf(fp, "[%0.3f] pid=%d %s\n", now.timeIntervalSince1970, getpid(), line.UTF8String ?: "");
    fflush(fp);
    fclose(fp);
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
    ZZFilterDebugFileLog(@"BUILD arch=%s", arch);
}
