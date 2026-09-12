#import <Foundation/Foundation.h>
#import <os/log.h>
#import "ZZDebug.h"

static os_log_t ZZDebugLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ log = os_log_create("com.zzfilterplugin", "debug"); });
    return log;
}

NSString *ZZFilterDebugLogPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *primary = @"/var/mobile/ZZFilterPlugin-v9.log";
        NSString *dir = [primary stringByDeletingLastPathComponent];
        BOOL ok = [[NSFileManager defaultManager] fileExistsAtPath:dir] ||
                  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        if (ok && [[NSFileManager defaultManager] isWritableFileAtPath:dir]) path = primary;
        else path = @"/tmp/ZZFilterPlugin-v9.log";
        if (![[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSData data] writeToFile:path atomically:YES];
    });
    return path;
}

void ZZFilterDebugWrite(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    @synchronized (ZZDebugLog) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:ZZFilterDebugLogPath()];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    }
    os_log(ZZDebugLog(), "%{public}s", message.UTF8String ?: "");
}

void ZZFilterDebugLogBuildInfo(void) {
#if defined(__arm64e__)
    const char *arch = "arm64e";
#elif defined(__arm64__)
    const char *arch = "arm64";
#else
    const char *arch = "unknown";
#endif
    ZZFilterDebugWrite(@"[ZZDebug] v9 loaded arch=%s iOS-min=16.0 log=%@", arch, ZZFilterDebugLogPath());
}
