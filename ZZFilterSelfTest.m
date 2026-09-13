#import <Foundation/Foundation.h>
#import "ZZProductFilter.h"
#import "ZZFilterURLProtocol.h"
#import "ZZSettings.h"
#import "ZZDebug.h"

static BOOL ZZAssert(BOOL condition, NSString *name) {
    if (!condition) {
        NSLog(@"[ZZSELFTEST] FAIL: %@", name);
        return NO;
    }
    NSLog(@"[ZZSELFTEST] PASS: %@", name);
    return YES;
}

BOOL ZZFilterDebugSelfTest(void) {
    @autoreleasepool {
        BOOL ok = YES;

        ZZProductFilter *f = [ZZProductFilter new];
        f.enabled = YES;
        f.minimumText = 100;
        f.maximumText = 500;
        f.minimumVersion = @"2.0";
        f.maximumVersion = @"5.0";

        NSDictionary *good = @{
            @"id": @"1", @"title": @"300", @"version": @"1.0.0", @"key": @"系统版本", @"value": @"iOS 3.1"
        };
        NSDictionary *low = @{
            @"id": @"2", @"title": @"50", @"version": @"1.0.0", @"systemVersion": @"iOS 3.1"
        };
        NSDictionary *high = @{
            @"id": @"3", @"title": @"800", @"version": @"1.0.0", @"iosVersion": @"iOS 3.1"
        };
        NSDictionary *old = @{
            @"id": @"4", @"title": @"300", @"version": @"1.0.0", @"value": @"iOS 1.9"
        };
        NSDictionary *newer = @{
            @"id": @"5", @"title": @"300", @"version": @"1.0.0", @"iosVersion": @"iOS 5.1"
        };

        ok &= ZZAssert([f shouldDisplayProduct:good], @"in-range item kept");
        ok &= ZZAssert(![f shouldDisplayProduct:low], @"below minimum removed");
        ok &= ZZAssert(![f shouldDisplayProduct:high], @"above maximum removed");
        ok &= ZZAssert(![f shouldDisplayProduct:old], @"below version removed");
        ok &= ZZAssert(![f shouldDisplayProduct:newer], @"above version removed");

        // Regression test for v26: attributes stored inside an NSArray must be
        // traversed instead of being rejected by ZZFindVersionDeep.
        NSDictionary *arrayNested = @{
            @"id": @"array-1",
            @"title": @"iPhone 15 Pro Max 256G",
            @"version": @"1.0.0",
            @"attrs": @[
                @{ @"key": @"颜色", @"value": @"黑色" },
                @{ @"key": @"系统版本", @"value": @"iOS 18.6.2" }
            ]
        };
        ok &= ZZAssert([ZZProductVersionFromDictionary(arrayNested) isEqualToString:@"18.6.2"], @"array attribute extracts system version");
        ok &= ZZAssert([f shouldDisplayProduct:arrayNested], @"array attribute in-range item kept");

        NSDictionary *mapped = @{
            @"itemId2AttrInfo": @{
                @"mapped-1": @[
                    @{ @"key": @"系统版本", @"value": @"iOS 26.4.1" }
                ]
            }
        };
        ok &= ZZAssert([ZZProductVersionFromDictionary(mapped) isEqualToString:@"26.4.1"], @"itemId2AttrInfo array extracts system version");

        NSData *json = [NSJSONSerialization dataWithJSONObject:@{
            @"items": @[good, low, high, old, newer]
        } options:0 error:nil];

        [ZZSettings shared].enabled = YES;
        [ZZSettings shared].minimumText = 100;
        [ZZSettings shared].maximumText = 500;
        [ZZSettings shared].minimumVersion = @"2.0";
        [ZZSettings shared].maximumVersion = @"5.0";

        NSError *error = nil;
        NSData *out = [ZZFilterURLProtocol filteredJSONData:json error:&error];
        NSDictionary *decoded = out ? [NSJSONSerialization JSONObjectWithData:out options:0 error:&error] : nil;
        NSArray *items = [decoded isKindOfClass:NSDictionary.class] ? decoded[@"items"] : nil;

        ok &= ZZAssert(error == nil, @"JSON filtering has no error");
        ok &= ZZAssert(items.count == 1, @"JSON result contains one item");
        ok &= ZZAssert([items.firstObject[@"id"] isEqual:@"1"], @"remaining item is expected");

        NSLog(@"[ZZSELFTEST] %@", ok ? @"ALL PASS" : @"FAILED");
        return ok;
    }
}
