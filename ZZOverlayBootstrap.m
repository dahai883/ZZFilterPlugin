#import <Foundation/Foundation.h>
#import "ZZOverlayController.h"

/// ObjC +load gives the overlay a second, independent initialization path.
/// It does not touch UIKit synchronously; all UI work is deferred to the main queue.
@interface ZZOverlayBootstrap : NSObject
@end

@implementation ZZOverlayBootstrap

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[ZZOverlay] +load bootstrap main-queue callback");
        [[ZZOverlayController shared] start];
    });
}

@end
