#import <Foundation/Foundation.h>
#import <os/log.h>
#import "ZZDebug.h"

static os_log_t ZZDebugLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ log = os_log_create("com.zzfilterplugin", "debug"); });
    return log;
}

NSString *ZZFilterDiagnosticLogPath(void) { return @"/tmp/ZZFilterPlugin-diagnostic.log"; }

void ZZFilterDiagnosticLogReset(void) {
    @try { [[NSFileManager defaultManager] removeItemAtPath:ZZFilterDiagnosticLogPath() error:nil]; } @catch (__unused NSException *e) {}
}

void ZZFilterDiagnosticLog(NSString *format, ...) {
    if (!format) return;
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *full = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
    @try {
        NSString *path = ZZFilterDiagnosticLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            [fh seekToEndOfFile]; [fh writeData:data]; [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
    os_log(ZZDebugLog(), "%{public}s", line.UTF8String ?: "");
}

void ZZFilterDebugLogBuildInfo(void) {
#if defined(__arm64e__)
    const char *arch = "arm64e";
#elif defined(__arm64__)
    const char *arch = "arm64";
#else
    const char *arch = "unknown";
#endif
    ZZFilterDiagnosticLog(@"BUILD arch=%s iOS-min=16.0", arch);
}
