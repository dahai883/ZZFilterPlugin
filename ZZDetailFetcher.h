#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZZDetailCompletion)(NSArray<NSDictionary *> *entries, NSError * _Nullable error);

FOUNDATION_EXPORT NSUInteger ZZDetailHTTPResponses(void);

@interface ZZDetailFetcher : NSObject
+ (instancetype)shared;
@property(nonatomic, strong) NSURLSession *session;

/// Fetches lightweight detail responses for product IDs. This is an
/// independent data-enrichment helper; it does not alter activation or
/// licensing state.
- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
                         baseURL:(NSURL *)baseURL
                       headers:(NSDictionary<NSString *, NSString *> * _Nullable)headers
                    completion:(ZZDetailCompletion)completion;

- (void)fetchDetailsForProductIDs:(NSArray<NSString *> *)productIDs
            jumpURLsByProductID:(NSDictionary<NSString *, NSURL *> * _Nullable)jumpURLsByProductID
                  sourceRequest:(NSURLRequest * _Nullable)sourceRequest
                        baseURL:(NSURL *)baseURL
                         headers:(NSDictionary<NSString *, NSString *> * _Nullable)headers
                      completion:(ZZDetailCompletion)completion;
@end

NS_ASSUME_NONNULL_END
