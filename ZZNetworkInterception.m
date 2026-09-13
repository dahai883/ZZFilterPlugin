#import "ZZNetworkInterception.h"
#import "ZZFilterURLProtocol.h"
#import <objc/runtime.h>

static NSMutableArray<NSHTTPCookieStorage *> *gCookieStorages;
static NSObject *gCookieLock;

static void ZZEnsureCookieRegistry(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCookieStorages = [NSMutableArray array];
        gCookieLock = [NSObject new];
    });
}

void ZZRegisterCookieStorage(NSHTTPCookieStorage *storage) {
    if (!storage) return;
    ZZEnsureCookieRegistry();
    @synchronized (gCookieLock) {
        if (![gCookieStorages containsObject:storage]) [gCookieStorages addObject:storage];
    }
}

NSArray<NSHTTPCookieStorage *> *ZZRegisteredCookieStorages(void) {
    ZZEnsureCookieRegistry();
    @synchronized (gCookieLock) { return gCookieStorages.copy; }
}

NSArray<NSHTTPCookie *> *ZZCookiesForURL(NSURL *url) {
    if (!url) return @[];
    NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^appendCookies)(NSArray<NSHTTPCookie *> *) = ^(NSArray<NSHTTPCookie *> *items) {
        for (NSHTTPCookie *cookie in items ?: @[]) {
            NSString *identity = [NSString stringWithFormat:@"%@|%@|%@|%@",
                                  cookie.name ?: @"", cookie.domain ?: @"", cookie.path ?: @"", cookie.value ?: @""];
            if (![seen containsObject:identity]) {
                [seen addObject:identity];
                [cookies addObject:cookie];
            }
        }
    };

    appendCookies([NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:url]);
    for (NSHTTPCookieStorage *storage in ZZRegisteredCookieStorages()) {
        appendCookies([storage cookiesForURL:url]);
    }
    return cookies.copy;
}

void ZZStoreResponseCookies(NSHTTPURLResponse *response, NSURL *url) {
    if (!response || !url) return;
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:url];
    if (!cookies.count) return;
    [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookies:cookies forURL:url mainDocumentURL:nil];
    for (NSHTTPCookieStorage *storage in ZZRegisteredCookieStorages()) {
        if (storage != NSHTTPCookieStorage.sharedHTTPCookieStorage) {
            [storage setCookies:cookies forURL:url mainDocumentURL:nil];
        }
    }
}

static void ZZAddProtocolToConfiguration(NSURLSessionConfiguration *configuration) {
    if (!configuration) return;
    ZZRegisterCookieStorage(configuration.HTTPCookieStorage);
    [ZZFilterURLProtocol installOnSessionConfiguration:configuration];
}

@interface NSURLSessionConfiguration (ZZFilterAutoInstall)
+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration;
+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration;
@end

@implementation NSURLSessionConfiguration (ZZFilterAutoInstall)

+ (NSURLSessionConfiguration *)zz_filter_defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_defaultSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] defaultSessionConfiguration intercepted; protocol installed cookieStorage=%p", configuration.HTTPCookieStorage);
    return configuration;
}

+ (NSURLSessionConfiguration *)zz_filter_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self zz_filter_ephemeralSessionConfiguration];
    ZZAddProtocolToConfiguration(configuration);
    NSLog(@"[ZZFilterNetwork] ephemeralSessionConfiguration intercepted; protocol installed cookieStorage=%p", configuration.HTTPCookieStorage);
    return configuration;
}

@end

void ZZInstallNetworkInterception(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZZEnsureCookieRegistry();
        ZZRegisterCookieStorage(NSHTTPCookieStorage.sharedHTTPCookieStorage);
        Class cls = [NSURLSessionConfiguration class];

        Method originalDefault = class_getClassMethod(cls, @selector(defaultSessionConfiguration));
        Method replacementDefault = class_getClassMethod(cls, @selector(zz_filter_defaultSessionConfiguration));
        if (originalDefault && replacementDefault) method_exchangeImplementations(originalDefault, replacementDefault);

        Method originalEphemeral = class_getClassMethod(cls, @selector(ephemeralSessionConfiguration));
        Method replacementEphemeral = class_getClassMethod(cls, @selector(zz_filter_ephemeralSessionConfiguration));
        if (originalEphemeral && replacementEphemeral) method_exchangeImplementations(originalEphemeral, replacementEphemeral);

        // Register the stores already attached to the stock configurations.
        NSURLSessionConfiguration *defaultConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSessionConfiguration *ephemeralConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        ZZRegisterCookieStorage(defaultConfig.HTTPCookieStorage);
        ZZRegisterCookieStorage(ephemeralConfig.HTTPCookieStorage);
        NSLog(@"[ZZFilterNetwork] interception installed; cookieStorages=%lu", (unsigned long)ZZRegisteredCookieStorages().count);
    });
}

__attribute__((constructor))
static void ZZNetworkInterceptionConstructor(void) {
    ZZInstallNetworkInterception();
}
