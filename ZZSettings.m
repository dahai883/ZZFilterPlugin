#import "ZZSettings.h"

static NSString * const kEnabled = @"ZZFilterEnabled";
static NSString * const kMinText = @"ZZFilterMinimumText";
static NSString * const kMaxText = @"ZZFilterMaximumText";
static NSString * const kMinVersion = @"ZZFilterMinimumVersion";
static NSString * const kMaxVersion = @"ZZFilterMaximumVersion";

@implementation ZZSettings

+ (instancetype)shared {
    static ZZSettings *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [ZZSettings new];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        s.enabled = [d objectForKey:kEnabled] ? [d boolForKey:kEnabled] : YES;
        s.minimumText = [d objectForKey:kMinText] ? [d integerForKey:kMinText] : 0;
        s.maximumText = [d objectForKey:kMaxText] ? [d integerForKey:kMaxText] : NSIntegerMax;
        s.minimumVersion = [d stringForKey:kMinVersion] ?: @"";
        s.maximumVersion = [d stringForKey:kMaxVersion] ?: @"";
    });
    return s;
}

- (void)save {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:self.enabled forKey:kEnabled];
    [d setInteger:self.minimumText forKey:kMinText];
    [d setInteger:self.maximumText forKey:kMaxText];
    [d setObject:self.minimumVersion ?: @"" forKey:kMinVersion];
    [d setObject:self.maximumVersion ?: @"" forKey:kMaxVersion];
    [d synchronize];
}

@end
