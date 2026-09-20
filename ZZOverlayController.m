#import "ZZOverlayController.h"
#import "ZZSettings.h"
#import "ZZRuntimeFiltering.h"
#import "ZZProductVisibility.h"
#import "ZZFilterURLProtocol.h"
#import "ZZDetailFetcher.h"
#import "ZZNetworkInterception.h"
#import "ZZProductFilter.h"
// Keep debug logging compatible with the iOS 17.5 SDK.
// os_log's format argument must be a compile-time constant; forwarding a
// variadic Objective-C format through a macro can trigger OS_LOG_STRING
// static-assert errors. NSLog is sufficient for this diagnostic build.

static const NSInteger ZZOverlayButtonTag = 0x5A5A01;

#define ZZOverlayLogInfo(fmt, ...) do { \
    NSLog(@"[ZZOverlay] " fmt, ##__VA_ARGS__); \
} while (0)

#define ZZOverlayLogError(fmt, ...) do { \
    NSLog(@"[ZZOverlay][ERROR] " fmt, ##__VA_ARGS__); \
} while (0)

@interface ZZVersionResultsController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *entries;
@property(nonatomic, weak) UIViewController *presentingVC;
@property(nonatomic) BOOL requestedMore;
@end

@interface ZZOverlayController ()
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic) BOOL started;
@property(nonatomic) NSUInteger installAttempts;
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

- (instancetype)init {
    self = [super init];
    if (self) {
        ZZOverlayLogInfo(@"controller init");
    }
    return self;
}

- (void)start {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }

    if (self.started) {
        ZZOverlayLogInfo(@"start called again");
        [self installButtonIfNeeded];
        return;
    }

    self.started = YES;
    self.installAttempts = 0;
    ZZOverlayLogInfo(@"start called; UIApplication=%@", UIApplication.sharedApplication);

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(sceneDidActivate:) name:UISceneDidActivateNotification object:nil];
    [nc addObserver:self selector:@selector(windowDidBecomeKey:) name:UIWindowDidBecomeKeyNotification object:nil];

    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    ZZOverlayLogInfo(@"applicationState at start=%ld", (long)state);
    if (state == UIApplicationStateActive) {
        [self applicationDidBecomeActive:nil];
    }

    [self scheduleInstallRetry:0.05];
    [self scheduleInstallRetry:0.5];
    [self scheduleInstallRetry:1.5];
    [self scheduleInstallRetry:3.0];
    [self scheduleInstallRetry:5.0];
    [self scheduleStatusRefresh];
}

- (void)stop {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self stop]; });
        return;
    }

    ZZOverlayLogInfo(@"stop called");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.button removeFromSuperview];
    self.button = nil;
    self.hostWindow = nil;
    self.started = NO;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)scheduleInstallRetry:(NSTimeInterval)delay {
    if (!self.started) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.started) return;
        ZZOverlayLogInfo(@"install retry after %.2fs", delay);
        [self installButtonIfNeeded];
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    (void)note;
    if (!self.started) return;
    ZZOverlayLogInfo(@"UIApplicationDidBecomeActive; scheduling UI install");
    // Match the reference implementation's lifecycle: wait until UIKit has
    // completed the activation transition before touching the host window.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.started) return;
        ZZOverlayLogInfo(@"active callback: installing button");
        [self installButtonIfNeeded];
        [self refreshButton];
    });
}

- (void)sceneDidActivate:(NSNotification *)note {
    if (!self.started) return;
    UIScene *scene = note.object;
    ZZOverlayLogInfo(@"UISceneDidActivate scene=%@ state=%ld", scene, (long)scene.activationState);
    [self installButtonIfNeeded];
}

- (void)windowDidBecomeKey:(NSNotification *)note {
    if (!self.started) return;
    UIWindow *window = (UIWindow *)note.object;
    ZZOverlayLogInfo(@"UIWindowDidBecomeKey window=%p hidden=%d alpha=%.2f level=%.2f root=%@",
                     window, window.hidden, window.alpha, window.windowLevel, window.rootViewController);
    [self installButtonIfNeeded];
}

- (UIWindow *)activeWindow {
    UIApplication *app = UIApplication.sharedApplication;
    ZZOverlayLogInfo(@"activeWindow: connectedScenes=%lu appWindows=%lu",
                     (unsigned long)app.connectedScenes.count,
                     (unsigned long)app.windows.count);

    UIWindow *fallback = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            ZZOverlayLogInfo(@"scene=%p activationState=%ld windows=%lu",
                             scene, (long)scene.activationState,
                             (unsigned long)windowScene.windows.count);

            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            UIWindow *keyWindow = windowScene.keyWindow;
            if (keyWindow && !keyWindow.hidden && keyWindow.alpha > 0.01 && keyWindow.rootViewController) {
                ZZOverlayLogInfo(@"activeWindow: using keyWindow=%p level=%.2f root=%@",
                                 keyWindow, keyWindow.windowLevel, keyWindow.rootViewController);
                return keyWindow;
            }

            for (UIWindow *window in windowScene.windows) {
                if (window.hidden || window.alpha <= 0.01 || !window.rootViewController) continue;
                if (!fallback || window.isKeyWindow) fallback = window;
                ZZOverlayLogInfo(@"candidate window=%p key=%d level=%.2f root=%@",
                                 window, window.isKeyWindow, window.windowLevel, window.rootViewController);
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        if (window.hidden || window.alpha <= 0.01 || !window.rootViewController) continue;
        if (!fallback || window.isKeyWindow) fallback = window;
        ZZOverlayLogInfo(@"legacy candidate window=%p key=%d level=%.2f root=%@",
                         window, window.isKeyWindow, window.windowLevel, window.rootViewController);
    }
#pragma clang diagnostic pop

    if (fallback) {
        ZZOverlayLogInfo(@"activeWindow: using fallback=%p", fallback);
    } else {
        ZZOverlayLogError(@"activeWindow: NO WINDOW FOUND");
    }
    return fallback;
}

- (UIViewController *)topViewControllerFrom:(UIViewController *)root {
    if (!root) return nil;
    UIViewController *current = root;

    while (current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
        current = current.presentedViewController;
    }
    if ([current isKindOfClass:UINavigationController.class]) {
        UIViewController *visible = ((UINavigationController *)current).visibleViewController;
        return [self topViewControllerFrom:visible ?: current];
    }
    if ([current isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)current).selectedViewController;
        return [self topViewControllerFrom:selected ?: current];
    }
    if ([current isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)current).viewControllers.lastObject;
        return [self topViewControllerFrom:last ?: current];
    }
    return current;
}

- (void)installButtonIfNeeded {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self installButtonIfNeeded]; });
        return;
    }
    if (!self.started) return;

    self.installAttempts += 1;
    UIWindow *window = [self activeWindow];
    if (!window) {
        ZZOverlayLogError(@"install #%lu: no host window", (unsigned long)self.installAttempts);
        if (self.installAttempts < 12) [self scheduleInstallRetry:1.0];
        return;
    }

    self.hostWindow = window;
    ZZOverlayLogInfo(@"install #%lu: hostWindow=%p bounds=%@ root=%@",
                     (unsigned long)self.installAttempts, window, NSStringFromCGRect(window.bounds), window.rootViewController);

    // The reference implementation uses a stable tag so it does not create
    // duplicate controls after the host app rebuilds its view hierarchy.
    UIView *existing = [window viewWithTag:ZZOverlayButtonTag];
    if ([existing isKindOfClass:UIButton.class]) {
        self.button = (UIButton *)existing;
        [window bringSubviewToFront:self.button];
        ZZOverlayLogInfo(@"reusing tagged button=%p frame=%@", self.button, NSStringFromCGRect(self.button.frame));
        [self refreshButton];
        return;
    }

    if (self.button.superview != window) {
        [self.button removeFromSuperview];

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = ZZOverlayButtonTag;
        CGFloat width = CGRectGetWidth(window.bounds);
        CGFloat height = CGRectGetHeight(window.bounds);
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat x = MAX(8.0, width - insets.right - 66.0);
        CGFloat y = MIN(MAX(insets.top + 80.0, height * 0.55),
                        MAX(insets.top + 80.0, height - insets.bottom - 66.0));
        button.frame = CGRectMake(x, y, 58.0, 58.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                  UIViewAutoresizingFlexibleTopMargin |
                                  UIViewAutoresizingFlexibleBottomMargin;
        button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
        button.layer.cornerRadius = 29.0;
        button.layer.masksToBounds = NO;
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.35;
        button.layer.shadowRadius = 7.0;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = UIColor.whiteColor.CGColor;
        [button setTitle:@"筛选" forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 3;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        button.accessibilityLabel = @"ZZFilterPlugin 筛选";
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(buttonPanned:)];
        [button addGestureRecognizer:pan];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(buttonLongPressed:)];
        longPress.minimumPressDuration = 0.6;
        [button addGestureRecognizer:longPress];

        [window addSubview:button];
        self.button = button;
        [window bringSubviewToFront:button];

        ZZOverlayLogInfo(@"BUTTON INSTALLED: button=%p superview=%p frame=%@ windowLevel=%.2f",
                         button, button.superview, NSStringFromCGRect(button.frame), window.windowLevel);
    } else {
        [window bringSubviewToFront:self.button];
        ZZOverlayLogInfo(@"button already installed: button=%p frame=%@", self.button, NSStringFromCGRect(self.button.frame));
    }

    [self refreshButton];
}

- (void)scheduleStatusRefresh {
    if (!self.started) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.started) return;
        [self refreshButton];
        [self scheduleStatusRefresh];
    });
}

static NSString *ZZCompactDiagnosticText(id value, NSUInteger maxLength) {
    if (![value isKindOfClass:NSString.class]) return @"-";
    NSString *text = [(NSString *)value copy];
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    if (maxLength > 0 && text.length > maxLength) {
        text = [[text substringToIndex:maxLength] stringByAppendingString:@"…"];
    }
    return text.length ? text : @"-";
}

- (NSString *)diagnosticSummary {
    NSUInteger hooks = ZZRuntimeFilteringHookCount();
    NSUInteger calls = ZZRuntimeFilteringCalls();
    NSUInteger processed = ZZFilterModelsProcessedCount();
    NSUInteger hidden = ZZFilterModelsHiddenCount();
    NSUInteger network = ZZNetworkInterceptedRequests();
    NSUInteger modified = ZZNetworkModifiedResponses();
    NSUInteger detailRequests = ZZDetailPrefetchRequests();
    NSUInteger observedDetailRequests = ZZObservedDetailRequests();
    NSUInteger observedDetailResponses = ZZObservedDetailResponses();
    NSUInteger observedDetail2xx = ZZObservedDetail2xxResponses();
    NSUInteger observedDetailVersionMatches = ZZObservedDetailVersionMatches();
    NSInteger observedDetailLastStatus = ZZObservedDetailLastStatus();
    NSString *observedDetailAllow = ZZCompactDiagnosticText(ZZObservedDetailLastAllow(), 32);
    NSString *observed2xxVersion = ZZCompactDiagnosticText(ZZObservedDetailLast2xxVersion(), 24);
    NSUInteger observed2xxBytes = ZZObservedDetailLast2xxBytes();
    NSString *observed2xxContentType = ZZCompactDiagnosticText(ZZObservedDetailLast2xxContentType(), 36);
    NSString *observed2xxURL = ZZCompactDiagnosticText(ZZObservedDetailLast2xxURL(), 72);
    NSString *observed2xxBody = ZZCompactDiagnosticText(ZZObservedDetailLast2xxBody(), 96);
    NSString *observedFailureURL = ZZCompactDiagnosticText(ZZObservedDetailLastFailureURL(), 72);
    NSString *observedFailureMethod = ZZCompactDiagnosticText(ZZObservedDetailLastFailureMethod(), 12);
    NSString *observedFailureBody = ZZCompactDiagnosticText(ZZObservedDetailLastFailureBody(), 96);
    NSUInteger detailResponses = ZZDetailHTTPResponses();
    NSUInteger detail2xx = ZZDetailHTTP2xxResponses();
    NSUInteger detailFailures = ZZDetailHTTPFailureResponses();
    NSInteger detailLastStatus = ZZDetailLastHTTPStatus();
    NSUInteger detailGET = ZZDetailGETRequests();
    NSUInteger detailPOSTForm = ZZDetailPOSTFormRequests();
    NSUInteger detailPOSTJSON = ZZDetailPOSTJSONRequests();

    // v54: keep this path deliberately boring. v53 used NSURL parsing and a
    // large nested stringWithFormat chain while the host app was on the main
    // thread; the crash report showed an Objective-C runtime-lock recursion
    // during diagnosticSummary. Build the message with appendString/appendFormat
    // and only pass known NSString instances to %@.
    NSMutableString *out = [NSMutableString stringWithCapacity:1200];
    [out appendString:@"插件已加载\n"];
    [out appendFormat:@"UI：Hook %lu / 调用 %lu\n", (unsigned long)hooks, (unsigned long)calls];
    [out appendFormat:@"商品：处理 %lu / 隐藏 %lu\n", (unsigned long)processed, (unsigned long)hidden];
    [out appendFormat:@"网络：拦截 %lu / 修改 %lu\n", (unsigned long)network, (unsigned long)modified];
    [out appendFormat:@"详情：预取 %lu / 观察 %lu / 响应 %lu\n", (unsigned long)detailRequests, (unsigned long)observedDetailRequests, (unsigned long)observedDetailResponses];
    [out appendFormat:@"响应：2xx %lu / 失败 %lu / 最近 %ld\n", (unsigned long)observedDetail2xx, (unsigned long)detailFailures, (long)observedDetailLastStatus];
    [out appendFormat:@"版本：解析 %lu / 命中 %lu\n", (unsigned long)observedDetailVersionMatches, (unsigned long)observedDetailVersionMatches];
    [out appendFormat:@"请求：GET %lu / 表单 %lu / JSON %lu\n", (unsigned long)detailGET, (unsigned long)detailPOSTForm, (unsigned long)detailPOSTJSON];
    [out appendFormat:@"实际响应：%lu / 2xx %lu / 失败 %lu\n", (unsigned long)detailResponses, (unsigned long)detail2xx, (unsigned long)detailFailures];
    [out appendFormat:@"最后HTTP：%ld\n", (long)detailLastStatus];
    [out appendString:@"最后失败："];
    if (![observedFailureURL isEqualToString:@"-"]) {
        [out appendString:observedFailureMethod];
        [out appendString:@" "];
        [out appendFormat:@"%ld ", (long)observedDetailLastStatus];
        [out appendString:observedFailureURL];
    } else {
        [out appendString:@"无"];
    }
    [out appendString:@"\nAllow："];
    [out appendString:observedDetailAllow];
    [out appendString:@"\n候选2xx："];
    if (![observed2xxURL isEqualToString:@"-"]) {
        [out appendString:observed2xxURL];
        [out appendString:@" / "];
        [out appendString:observed2xxContentType];
        [out appendFormat:@" / %luB", (unsigned long)observed2xxBytes];
    } else {
        [out appendString:@"无"];
    }
    [out appendString:@"\n候选版本："];
    [out appendString:observed2xxVersion];
    [out appendString:@"\n候选Body："];
    [out appendString:observed2xxBody];
    [out appendString:@"\n失败Body："];
    [out appendString:observedFailureBody];
    return out;
}

- (void)showDiagnosticsFrom:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZZFilterPlugin 状态"
                                                                     message:[self diagnosticSummary]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"刷新" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        ZZInstallRuntimeFiltering();
        [self refreshButton];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置统计" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        ZZResetFilterDiagnostics();
        [self refreshButton];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)buttonPanned:(UIPanGestureRecognizer *)gesture {
    if (!self.button || !self.hostWindow) return;
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

- (void)buttonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !NSThread.isMainThread) return;
    UIWindow *window = self.hostWindow ?: [self activeWindow];
    UIViewController *vc = [self topViewControllerFrom:window.rootViewController];
    if (vc) [self showDiagnosticsFrom:vc];
}

- (void)buttonTapped:(UIButton *)sender {
    (void)sender;
    if (!NSThread.isMainThread) return;

    UIWindow *window = self.hostWindow ?: [self activeWindow];
    if (!window) {
        ZZOverlayLogError(@"buttonTapped: no window");
        return;
    }
    UIViewController *vc = [self topViewControllerFrom:window.rootViewController];
    ZZOverlayLogInfo(@"buttonTapped: window=%p topVC=%@", window, vc);
    if (!vc) return;
    [self presentSettingsFrom:vc];
}

- (NSString *)summary {
    ZZSettings *s = ZZSettings.shared;
    NSString *minVer = s.minimumVersion.length ? s.minimumVersion : @"不限";
    NSString *maxVer = s.maximumVersion.length ? s.maximumVersion : @"不限";
    return [NSString stringWithFormat:@"状态：%@\n系统版本范围：%@ ～ %@\n已缓存版本商品：%lu\n\nUI Hook: %lu\n处理: %lu\n隐藏: %lu\n网络: %lu / 修改: %lu",
            s.enabled ? @"开启" : @"关闭", minVer, maxVer,
            (unsigned long)[ZZProductVisibility.shared cachedEntryCount],
            (unsigned long)ZZRuntimeFilteringHookCount(),
            (unsigned long)ZZFilterModelsProcessedCount(),
            (unsigned long)ZZFilterModelsHiddenCount(),
            (unsigned long)ZZNetworkInterceptedRequests(),
            (unsigned long)ZZNetworkModifiedResponses()];
}

- (void)showVersionResultsFrom:(UIViewController *)vc {
    NSArray<NSDictionary *> *entries = [ZZProductVisibility.shared cachedEntriesMatchingCurrentVersionRange];
    ZZVersionResultsController *results = [[ZZVersionResultsController alloc] initWithStyle:UITableViewStylePlain];
    results.entries = entries;
    results.presentingVC = vc;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:results];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 18.0;
    }
    [vc presentViewController:nav animated:YES completion:nil];
}

- (void)presentSettingsFrom:(UIViewController *)vc {
    ZZSettings *s = ZZSettings.shared;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZZFilterPlugin"
                                                                   message:[self summary]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最低系统版本（如 18.0.0）";
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.text = s.minimumVersion ?: @"";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"最高系统版本（如 26.6.1）";
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.text = s.maximumVersion ?: @"";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"查看系统版本结果" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf showVersionResultsFrom:vc];
    }]];
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
        NSString *minVer = fields.count > 0 ? fields[0].text : @"";
        NSString *maxVer = fields.count > 1 ? fields[1].text : @"";
        ZZSettings *settings = ZZSettings.shared;
        settings.minimumText = 0;
        settings.maximumText = NSIntegerMax;
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
    [vc presentViewController:alert animated:YES completion:^{
        ZZOverlayLogInfo(@"settings alert presented from %@", vc);
    }];
}

- (void)refreshButton {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshButton]; });
        return;
    }
    if (!self.button) return;
    NSUInteger hooks = ZZRuntimeFilteringHookCount();
    NSUInteger hidden = ZZFilterModelsHiddenCount();
    NSString *mark = hooks > 0 ? @"✓" : @"!";
    NSString *title = [NSString stringWithFormat:@"筛选\n%@ UI:%lu\n隐:%lu", mark, (unsigned long)hooks, (unsigned long)hidden];
    [self.button setTitle:title forState:UIControlStateNormal];
    self.button.alpha = ZZSettings.shared.enabled ? 1.0 : 0.55;
    ZZOverlayLogInfo(@"refreshButton enabled=%d hooks=%lu processed=%lu hidden=%lu network=%lu modified=%lu", ZZSettings.shared.enabled, (unsigned long)hooks, (unsigned long)ZZFilterModelsProcessedCount(), (unsigned long)hidden, (unsigned long)ZZNetworkInterceptedRequests(), (unsigned long)ZZNetworkModifiedResponses());
}

@end

@interface ZZVersionResultCell : UITableViewCell
@property(nonatomic, copy) void (^openHandler)(void);
@property(nonatomic, copy) void (^copyHandler)(void);
@end

@implementation ZZVersionResultCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) self.selectionStyle = UITableViewCellSelectionStyleNone;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.numberOfLines = 0;
    self.detailTextLabel.numberOfLines = 0;
}
@end

@implementation ZZVersionResultsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"系统版本筛选 · %lu 条", (unsigned long)self.entries.count];
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 112.0;
    self.tableView.allowsSelection = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 16, 0);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"加载更多" style:UIBarButtonItemStylePlain target:self action:@selector(loadMore)];
    if (self.entries.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
        empty.text = @"没有已确认属于当前系统版本范围的商品\n请返回列表并等待详情缓存后再打开本页";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        empty.textColor = UIColor.secondaryLabelColor;
        [empty sizeToFit];
        self.tableView.backgroundView = empty;
    }
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.requestedMore && self.entries.count <= 20) {
        self.requestedMore = YES;
        [self loadMore];
    }
}

- (void)loadMore {
    UIViewController *vc = self.presentingVC;
    if (!vc) return;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.navigationItem.rightBarButtonItem.title = @"加载中…";
    ZZRequestAdditionalListingPages(vc, 3);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray *updated = [ZZProductVisibility.shared cachedEntriesMatchingCurrentVersionRange];
        self.entries = updated ?: @[];
        self.title = [NSString stringWithFormat:@"系统版本筛选 · %lu 条", (unsigned long)self.entries.count];
        self.navigationItem.rightBarButtonItem.enabled = YES;
        self.navigationItem.rightBarButtonItem.title = @"加载更多";
        self.tableView.backgroundView = nil;
        if (self.entries.count == 0) {
            UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
            empty.text = @"没有已确认属于当前系统版本范围的商品\n请返回列表并等待详情缓存后再打开本页";
            empty.textAlignment = NSTextAlignmentCenter;
            empty.numberOfLines = 0;
            empty.textColor = UIColor.secondaryLabelColor;
            self.tableView.backgroundView = empty;
        }
        [self.tableView reloadData];
    });
}

static NSString *ZZCleanDisplayTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || !title.length) return @"商品";

    // Display-only cleanup: remove material/network labels requested by the user.
    // The underlying product dictionary and navigation URL are left untouched.
    NSString *clean = [title stringByReplacingOccurrencesOfString:@"钛金属" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"全网通" withString:@""];

    // Tidy whitespace/punctuation left behind by the removal.
    clean = [clean stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    clean = [clean stringByReplacingOccurrencesOfString:@" ｜  " withString:@" ｜ "];
    clean = [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : @"商品";
}

static NSString *ZZEntryTitle(NSDictionary *d) {
    for (NSString *key in @[@"title", @"name", @"itemTitle", @"goodsName", @"productName"]) {
        id v = d[key];
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return ZZCleanDisplayTitle(v);
    }
    return @"商品";
}

static NSString *ZZEntryPrice(NSDictionary *d) {
    for (NSString *key in @[@"price", @"sellPrice", @"salePrice", @"currentPrice", @"amount"]) {
        id v = d[key];
        if (v && [v respondsToSelector:@selector(description)]) return [v description];
    }
    return @"-";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"ZZVersionResultCell";
    ZZVersionResultCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[ZZVersionResultCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
    NSDictionary *d = self.entries[indexPath.row];
    NSString *title = ZZEntryTitle(d);
    NSString *version = ZZProductVersionFromDictionary(d);
    NSString *pid = ZZProductIDFromInfo(d);
    NSString *price = ZZEntryPrice(d);
    NSString *urlString = [ZZProductVisibility.shared cachedURLForProductID:pid];

    // Put the system version directly in the product name so the user can
    // compare versions without opening each item.
    NSString *displayTitle = title;
    if (version.length) {
        NSString *marker = [NSString stringWithFormat:@"iOS %@", version];
        if (![title localizedCaseInsensitiveContainsString:marker]) {
            displayTitle = [NSString stringWithFormat:@"%@ ｜ %@", title, marker];
        }
    }

    NSMutableString *detail = [NSMutableString stringWithFormat:@"¥%@", price];
    if (pid.length) [detail appendFormat:@"  |  ID %@", pid];
    if (urlString.length) [detail appendString:@"\n商品链接：可打开 / 可复制"];
    else [detail appendString:@"\n商品链接：当前未从列表响应获取"];

    cell.textLabel.text = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(indexPath.row + 1), displayTitle];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;

    // Put action buttons in the accessory area so every result has a direct
    // action, matching the reference UI's "复制链接 / 打开" behavior.
    UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 92, 36)];
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    copyButton.frame = CGRectMake(0, 0, 44, 36);
    [copyButton setTitle:@"复制" forState:UIControlStateNormal];
    copyButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    copyButton.tag = indexPath.row;
    [copyButton addTarget:self action:@selector(copyResult:) forControlEvents:UIControlEventTouchUpInside];
    copyButton.enabled = urlString.length > 0;

    UIButton *openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    openButton.frame = CGRectMake(48, 0, 44, 36);
    [openButton setTitle:@"打开" forState:UIControlStateNormal];
    openButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    openButton.tag = indexPath.row;
    [openButton addTarget:self action:@selector(openResult:) forControlEvents:UIControlEventTouchUpInside];
    openButton.enabled = urlString.length > 0;

    [accessory addSubview:copyButton];
    [accessory addSubview:openButton];
    cell.accessoryView = accessory;
    return cell;
}

- (void)copyResult:(UIButton *)sender {
    if ((NSUInteger)sender.tag >= self.entries.count) return;
    NSDictionary *d = self.entries[sender.tag];
    NSString *pid = ZZProductIDFromInfo(d);
    NSString *url = [ZZProductVisibility.shared cachedURLForProductID:pid];
    if (!url.length) return;
    UIPasteboard.generalPasteboard.string = url;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已复制" message:@"商品链接已复制到剪贴板。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openResult:(UIButton *)sender {
    if ((NSUInteger)sender.tag >= self.entries.count) return;
    NSDictionary *d = self.entries[sender.tag];
    NSString *pid = ZZProductIDFromInfo(d);
    NSString *urlString = [ZZProductVisibility.shared cachedURLForProductID:pid];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end
