#import "ZZDebug.h"
#import <os/log.h>
#import <unistd.h>

static os_log_t ZZDebugLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.zzfilterplugin", "debug");
    });
    return log;
}

NSString *ZZDiagLogPath(void) {
    return @"/var/mobile/ZZFilterPlugin-diagnostic.log";
}

void ZZDiagLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"%@ [pid=%d] %@\n", [NSDate date], getpid(), message ?: @""];
    @try {
        NSString *path = ZZDiagLogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        unsigned long long size = [attrs fileSize];
        if (size > 2 * 1024 * 1024) {
            NSString *tail = [line copy];
            [tail writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (__unused NSException *e) {
    }

    os_log(ZZDebugLog(), "%{public}@", message ?: @"");
}

void ZZFilterDebugLogBuildInfo(void) {
#if defined(__arm64e__)
    const char *arch = "arm64e";
#elif defined(__arm64__)
    const char *arch = "arm64";
#else
    const char *arch = "unknown";
#endif
    ZZDiagLog(@"BUILD arch=%s iOS-min=16.0", arch);
}
