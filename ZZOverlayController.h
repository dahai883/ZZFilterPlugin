#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Independent UI controller for the user's own/authorized host app.
/// Presents a small floating button and a settings panel for ZZFilterSettings.
@interface ZZOverlayController : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)refreshButton;
@end

NS_ASSUME_NONNULL_END
