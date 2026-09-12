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
    NSLog(@"[ZZOverlay] CONSTRUCTOR CALLED");
    ZZFilterDebugFileLog(@"CONSTRUCTOR loaded");
    ZZInstallNetworkInterception();
    ZZInstallUIFiltering();
    ZZInstallRuntimeFiltering();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
            ZZInstallRuntimeFiltering();
        }];
    });
    // Keep constructor work minimal. UI setup is deferred to the main queue;
    // ZZOverlayBootstrap +load provides a second initialization path.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[ZZOverlay] constructor main-queue callback");
        ZZFilterDebugFileLog(@"MAIN_QUEUE callback");
        [[ZZOverlayController shared] start];
    });
}

/// Reference-architecture entry points for independent model/list filtering.
/// These are intentionally activation-free.
void ZZInstallUIFiltering(void) {
    NSLog(@"[ZZFilterUI] UI filtering layer initialized");
    ZZInstallRuntimeFiltering();
}

