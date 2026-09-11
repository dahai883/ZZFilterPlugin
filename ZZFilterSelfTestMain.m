#import <Foundation/Foundation.h>
#import "ZZDebug.h"

int main(void) {
    @autoreleasepool {
        ZZFilterDebugLogBuildInfo();
        return ZZFilterDebugSelfTest() ? 0 : 1;
    }
}
