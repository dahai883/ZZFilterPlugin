#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZZFilterURLProtocol : NSURLProtocol
+ (void)installOnSessionConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSData * _Nullable)filteredJSONData:(NSData *)data error:(NSError **)error;
@end

FOUNDATION_EXPORT NSUInteger ZZNetworkInterceptedRequests(void);
FOUNDATION_EXPORT NSUInteger ZZNetworkModifiedResponses(void);

NS_ASSUME_NONNULL_END
