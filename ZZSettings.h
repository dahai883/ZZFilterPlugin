#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZZSettings : NSObject
+ (instancetype)shared;
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSInteger minimumText;
@property(nonatomic) NSInteger maximumText;
@property(nonatomic, copy) NSString *minimumVersion;
@property(nonatomic, copy) NSString *maximumVersion;
- (void)save;
@end

NS_ASSUME_NONNULL_END
