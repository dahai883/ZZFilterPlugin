#import <Foundation/Foundation.h>
#import "ZZFilterURLProtocol.h"
#import "ZZSettings.h"

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
