#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZZDetailCompletion)(NSArray<NSDictionary *> *entries, NSError * _Nullable error);

@interface ZZDetailFetcher : NSObject
@property(nonatomic, strong) NSURLSession *session;
- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
                              baseURL:(NSURL *)baseURL
                          completion:(ZZDetailCompletion)completion;
@end

NS_ASSUME_NONNULL_END
