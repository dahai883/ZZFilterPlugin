#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZZProductFilter : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSInteger minimumText;
@property(nonatomic) NSInteger maximumText;
@property(nonatomic, copy) NSString *minimumVersion;
@property(nonatomic, copy) NSString *maximumVersion;

- (BOOL)shouldDisplayProduct:(NSDictionary *)product;
- (NSArray<NSDictionary *> *)filteredProducts:(NSArray<NSDictionary *> *)products;
@end

FOUNDATION_EXPORT NSString *ZZProductVersionFromDictionary(NSDictionary *product);

NS_ASSUME_NONNULL_END
