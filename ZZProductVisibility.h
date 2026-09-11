#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Independent product-visibility cache modeled after the behavior observed
/// in the supplied reference binary. It does not contain activation logic.
@interface ZZProductVisibility : NSObject
+ (instancetype)shared;
- (void)recordEntries:(NSArray *)entries forProductIDs:(NSArray<NSString *> *)productIDs;
- (BOOL)shouldDisplayProductID:(NSString *)productID;
@property(nonatomic, copy) NSArray<NSString *> *versions;
@end

FOUNDATION_EXPORT NSString *ZZProductIDFromInfo(NSDictionary *info);
FOUNDATION_EXPORT BOOL ZZShouldKeepModel(id model);
FOUNDATION_EXPORT NSArray *ZZFilteredModels(NSArray *models);
FOUNDATION_EXPORT id ZZFilterRenderedData(id data);

NS_ASSUME_NONNULL_END
