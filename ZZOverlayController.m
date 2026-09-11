#import "ZZOverlayController.h"
#import "ZZSettings.h"

static const NSInteger ZZOverlayButtonTag = 0x5A5A01;

@interface ZZOverlayController ()
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic) BOOL started;
@end

@implementation ZZOverlayController

+ (instancetype)shared {
    static ZZOverlayController *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [ZZOverlayController new];
    });
    return shared;
}

- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    self.started = YES;
    [self installButtonIfNeeded];
}

- (void)stop {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self stop]; });
        return;
    }
    [self.button removeFromSuperview];
    self.button = nil;
    self.hostWindow = nil;
    self.started = NO;
}

- (UIWindow *)activeWindow {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                    return window;
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        if (!window.hidden && window.alpha > 0.01 && window.rootViewController) return window;
    }
#pragma clang diagnostic pop
    return nil;
}

- (UIViewController *)topViewControllerFrom:(UIViewController *)root {
    UIViewController *current = root;
    while (current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
        current = current.presentedViewController;
    }
    if ([current isKindOfClass:UINavigationController.class]) {
        return [self topViewControllerFrom:((UINavigationController *)current).visibleViewController ?: current];
    }
    if ([current isKindOfClass:UITabBarController.class]) {
        return [self topViewControllerFrom:((UITabBarController *)current).selectedViewController ?: current];
    }
    return current;
}

- (void)installButtonIfNeeded {
    UIWindow *window = [self activeWindow];
    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.started) [self installButtonIfNeeded];
        });
        return;
    }
    self.hostWindow = window;
    if (self.button.superview == window) return;

    [self.button removeFromSuperview];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = ZZOverlayButtonTag;
    button.frame = CGRectMake(CGRectGetWidth(window.bounds) - 78.0,
                              CGRectGetHeight(window.bounds) * 0.55,
                              58.0, 58.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    button.layer.cornerRadius = 29.0;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.25;
    button.layer.shadowRadius = 6.0;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    [button setTitle:@"筛选" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
    self.button = button;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(buttonPanned:)];
    [button addGestureRecognizer:pan];
}

- (void)buttonPanned:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [gesture translationInView:self.hostWindow];
        CGPoint center = self.button.center;
        center.x += delta.x;
        center.y += delta.y;
        CGFloat halfW = CGRectGetWidth(self.button.bounds) / 2.0;
        CGFloat halfH = CGRectGetHeight(self.button.bounds) / 2.0;
        center.x = MAX(halfW + 8.0, MIN(CGRectGetWidth(self.hostWindow.bounds) - halfW - 8.0, center.x));
        center.y = MAX(halfH + 8.0, MIN(CGRectGetHeight(self.hostWindow.bounds) - halfH - 8.0, center.y));
        self.button.center = center;
        [gesture setTranslation:CGPointZero inView:self.hostWindow];
    }
}

- (void)buttonTapped:(UIButton *)sender {
    if (!NSThread.isMainThread) return;
    UIWindow *window = self.hostWindow ?: [self activeWindow];
    UIViewController *vc = [self topViewControllerFrom:window.rootViewController];
    if (!vc) return;
    [self presentSettingsFrom:vc];
}

- (NSString *)summary {
    ZZSettings *s = ZZSettings.shared;
    NSString *minText = s.minimumText > 0 ? [NSString stringWithFormat:@"%ld", (long)s.minimumText] : @"不限";
    NSString *maxText = s.maximumText < NSIntegerMax ? [NSString stringWithFormat:@"%ld", (long)s.maximumText] : @"不限";
    NSString *minVer = s.minimumVersion.length ? s.minimumVersion : @"不限";
    NSString *maxVer = s.maximumVersion.length ? s.maximumVersion : @"不限";
    return [NSString stringWithFormat:@"状态：%@\n数值范围：%@ ～ %@\n版本范围：%@ ～ %@",
            s.enabled ? @"开启" : @"关闭", minText, maxText, minVer, maxVer];
}

- (void)presentSettingsFrom:(UIViewController *)vc {
    ZZSettings *s = ZZSettings.shared;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZZFilterPlugin"
                                                                   message:[self summary]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最小数值（留空=不限）";
        field.keyboardType = UIKeyboardTypeNumberPad;
        if (s.minimumText > 0) field.text = [NSString stringWithFormat:@"%ld", (long)s.minimumText];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最大数值（留空=不限）";
        field.keyboardType = UIKeyboardTypeNumberPad;
        if (s.maximumText < NSIntegerMax) field.text = [NSString stringWithFormat:@"%ld", (long)s.maximumText];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最低版本（如 1.2.3）";
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.text = s.minimumVersion ?: @"";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最高版本（如 2.0.0）";
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.text = s.maximumVersion ?: @"";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:s.enabled ? @"关闭过滤" : @"开启过滤"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *action) {
        ZZSettings *settings = ZZSettings.shared;
        settings.enabled = !settings.enabled;
        [settings save];
        [weakSelf refreshButton];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存范围" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSArray<UITextField *> *fields = alert.textFields;
        NSString *minText = fields.count > 0 ? fields[0].text : @"";
        NSString *maxText = fields.count > 1 ? fields[1].text : @"";
        NSString *minVer = fields.count > 2 ? fields[2].text : @"";
        NSString *maxVer = fields.count > 3 ? fields[3].text : @"";

        ZZSettings *settings = ZZSettings.shared;
        settings.minimumText = minText.integerValue;
        settings.maximumText = maxText.length ? maxText.integerValue : NSIntegerMax;
        settings.minimumVersion = minVer ?: @"";
        settings.maximumVersion = maxVer ?: @"";
        [settings save];
        [weakSelf refreshButton];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        ZZSettings *settings = ZZSettings.shared;
        settings.enabled = YES;
        settings.minimumText = 0;
        settings.maximumText = NSIntegerMax;
        settings.minimumVersion = @"";
        settings.maximumVersion = @"";
        [settings save];
        [weakSelf refreshButton];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)refreshButton {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshButton]; });
        return;
    }
    self.button.alpha = ZZSettings.shared.enabled ? 1.0 : 0.55;
}

@end
