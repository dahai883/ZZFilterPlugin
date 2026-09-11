#import "ZZNetworkInterception.h"
#import "ZZFilterURLProtocol.h"
#import <objc/runtime.h>

static void ZZAddProtocolToConfiguration(NSURLSessionConfiguration *configuration) {
    if (!configuration) return;
    [ZZFilterURLProtocol installOnSessionConfiguration:configuration];
}

@interface NSURLSessionConfiguration (ZZFilterAutoInstall)
+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration;
@end

@implementation NSURLSessionConfiguration (ZZFilterAutoInstall)

+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_defaultSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] defaultSessionConfiguration intercepted; protocol installed");
    return configuration;
}

+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_ephemeralSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] ephemeralSessionConfiguration intercepted; protocol installed");
    return configuration;
}

@end

void ZZInstallNetworkInterception(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [NSURLSessionConfiguration class];

        Method originalDefault = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
        Method replacementDefault = class_getClassMethod(cls, @selector(zz_filter_defaultSessionConfiguration));
        if (originalDefault && replacementDefault) {
            method_exchangeImplementations(originalDefault, replacementDefault);
        }

        Method originalEphemeral = class_getClassMethod(cls, @selector(ephemeralSessionConfiguration));
        Method replacementEphemeral = class_getClassMethod(cls, @selector(zz_filter_ephemeralSessionConfiguration));
        if (originalEphemeral && replacementEphemeral) {
            method_exchangeImplementations(originalEphemeral, replacementEphemeral);
        }

        NSLog(@"[ZZFilterNetwork] automatic NSURLSessionConfiguration interception installed");
    });
}

__attribute__((constructor))
static void ZZNetworkInterceptionConstructor(void) {
    ZZInstallNetworkInterception();
}
