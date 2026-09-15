#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZZDetailCompletion)(NSArray<NSDictionary *> *entries, NSError * _Nullable error);

FOUNDATION_EXPORT NSUInteger ZZDetailHTTPResponses(void);
FOUNDATION_EXPORT NSUInteger ZZDetailHTTP2xxResponses(void);
FOUNDATION_EXPORT NSUInteger ZZDetailHTTPFailureResponses(void);
FOUNDATION_EXPORT NSInteger ZZDetailLastHTTPStatus(void);
FOUNDATION_EXPORT NSUInteger ZZDetailGETRequests(void);
FOUNDATION_EXPORT NSUInteger ZZDetailPOSTFormRequests(void);
FOUNDATION_EXPORT NSUInteger ZZDetailPOSTJSONRequests(void);

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

/// Validates a detail HTTP response and extracts one normalized entry when the
/// response is a successful 2xx JSON/text payload. This mirrors the safe
/// response-validation boundary of the reference implementation without
/// touching activation, licensing, or signature state.
- (NSDictionary * _Nullable)entryFromData:(NSData * _Nullable)data
                                response:(NSURLResponse * _Nullable)response
                                   error:(NSError * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
