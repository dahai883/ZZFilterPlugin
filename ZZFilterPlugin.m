#import <Foundation/Foundation.h>
#import "ZZFilterURLProtocol.h"
#import "ZZSettings.h"
#import "ZZOverlayController.h"
#import "ZZNetworkInterception.h"
#import "ZZRuntimeFiltering.h"
#import "ZZDebug.h"

/// Public entry point for an authorized host application.
/// The host should call this and use the returned configuration when
/// creating its own NSURLSession.
NSURLSessionConfiguration *ZZFilterMakeSessionConfiguration(void) {
    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    [ZZFilterURLProtocol installOnSessionConfiguration:configuration];
    return configuration;
}

void ZZFilterSetEnabled(BOOL enabled) {
    ZZSettings.shared.enabled = enabled;
    [ZZSettings.shared save];
    [[ZZOverlayController shared] refreshButton];
}

void ZZFilterSetTextRange(NSInteger minimum, NSInteger maximum) {
    ZZSettings.shared.minimumText = minimum;
    ZZSettings.shared.maximumText = maximum;
    [ZZSettings.shared save];
}

void ZZFilterSetVersionRange(NSString *minimum, NSString *maximum) {
    ZZSettings.shared.minimumVersion = minimum ?: @"";
    ZZSettings.shared.maximumVersion = maximum ?: @"";
    [ZZSettings.shared save];
}

void ZZInstallUIFiltering(void);

__attribute__((constructor))
static void ZZFilterPluginLoaded(void) {
    ZZFilterDebugLogBuildInfo();
    ZZFilterDebugWrite(@"[ZZPlugin] constructor called");
    ZZInstallNetworkInterception();
    ZZInstallUIFiltering();
    ZZInstallRuntimeFiltering();
    // V11 repeatedly enumerated every Objective-C class/method once per second.
    // On ZhuanZhuan this is over a million methods per scan and can consume a
    // full CPU core. V12 uses only two bounded startup retries instead.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZZInstallRuntimeFiltering(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZZInstallRuntimeFiltering(); });
    // Keep constructor work minimal. UI setup is deferred to the main queue;
    // ZZOverlayBootstrap +load provides a second initialization path.
    dispatch_async(dispatch_get_main_queue(), ^{
        ZZFilterDebugWrite(@"[ZZPlugin] constructor main-queue callback");
        [[ZZOverlayController shared] start];
    });
}

/// Reference-architecture entry points for independent model/list filtering.
/// These are intentionally activation-free.
void ZZInstallUIFiltering(void) {
    ZZFilterDebugWrite(@"[ZZFilterUI] UI filtering layer initialized");
    ZZInstallRuntimeFiltering();
}

