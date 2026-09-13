#import "ZZRuntimeFiltering.h"
#import "ZZDebug.h"

// V14 deliberately does not perform global Objective-C runtime scanning or
// message-forwarding hooks. V12/V13 diagnostics showed that broad runtime
// discovery could consume excessive CPU and trigger a watchdog termination.
// UI counters remain available for compatibility with the existing overlay.

static NSUInteger ZZRuntimeCalls = 0;

void ZZInstallRuntimeFiltering(void) {
    ZZFilterDebugWrite(@"[ZZFilterUI] v14 runtime UI hook disabled; using network/detail filtering path");
}

NSUInteger ZZRuntimeFilteringHookCount(void) { return 0; }
NSUInteger ZZRuntimeFilteringCalls(void) { return ZZRuntimeCalls; }
NSUInteger ZZRuntimeCandidateCount(void) { return 0; }
NSString *ZZRuntimeDiagnosticSummary(void) {
    return @"V14: UI runtime 扫描已关闭（稳定性保护）；系统版本筛选走列表响应 + 商品详情缓存";
}
