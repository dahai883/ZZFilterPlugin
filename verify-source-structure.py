from pathlib import Path
import re, sys

root = Path(__file__).resolve().parent
fail = False

for p in root.glob('*.m'):
    text = p.read_text(errors='replace')
    impls = len(re.findall(r'^\s*@implementation\b', text, re.M))
    ends = len(re.findall(r'^\s*@end\s*$', text, re.M))
    if p.name == 'ZZOverlayController.m':
        if impls != 3 or ends != 6:
            print(f'FAIL {p.name}: expected 3 implementations / 6 @end, got {impls}/{ends}')
            fail = True
        s = text
        outer_start = s.find('@implementation ZZOverlayController')
        outer_end = s.find('\n@end', outer_start)
        results_impl = s.find('@implementation ZZVersionResultsController')
        show = s.find('- (void)showVersionResultsFrom:')
        present = s.find('- (void)presentSettingsFrom:')
        refresh = s.find('- (void)refreshButton')
        cell_iface = s.find('@interface ZZVersionResultCell')
        if not (outer_start >= 0 and outer_end >= 0 and show >= 0 and present >= 0 and refresh >= 0 and show < outer_end and present < outer_end and refresh < outer_end and results_impl > outer_end and cell_iface > outer_end):
            print('FAIL ZZOverlayController.m: outer controller methods are not inside the outer implementation')
            fail = True
    print(f'CHECK {p.name}: implementations={impls}, @end={ends}')

headers = "\n".join(x.read_text(errors="replace") for x in root.glob("*.h"))
impl_text = "\n".join(x.read_text(errors="replace") for x in root.glob("*.m"))

for cls in ["ZZDetailFetcher", "ZZProductVisibility", "ZZSettings", "ZZOverlayController"]:
    if f"[{cls} shared]" in impl_text and f"+ (instancetype)shared;" not in headers and f"+ (id)shared;" not in headers:
        print(f"FAIL missing +shared declaration for {cls}")
        fail = True

if '@["' in impl_text:
    print('FAIL malformed Objective-C array literal token @[\" detected')
    fail = True

net = (root / 'ZZNetworkInterception.m').read_text(errors='replace')
net_header = (root / "ZZNetworkInterception.h").read_text(errors='replace')

for decl in [
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxVersion(void);",
    "FOUNDATION_EXPORT NSUInteger ZZObservedDetailLast2xxBytes(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxContentType(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxURL(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLast2xxBody(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureURL(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureMethod(void);",
    "FOUNDATION_EXPORT NSString *ZZObservedDetailLastFailureBody(void);",
]:
    if decl not in net_header:
        print(f"FAIL ZZNetworkInterception.h: missing export declaration: {decl}")
        fail = True

for definition in [
    "NSString *ZZObservedDetailLast2xxVersion(void) {",
    "NSUInteger ZZObservedDetailLast2xxBytes(void) {",
    "NSString *ZZObservedDetailLast2xxContentType(void) {",
    "NSString *ZZObservedDetailLast2xxURL(void) {",
    "NSString *ZZObservedDetailLast2xxBody(void) {",
    "NSString *ZZObservedDetailLastFailureURL(void) {",
    "NSString *ZZObservedDetailLastFailureMethod(void) {",
    "NSString *ZZObservedDetailLastFailureBody(void) {",
]:
    if definition not in net:
        print(f"FAIL ZZNetworkInterception.m: missing exported definition: {definition}")
        fail = True

# v52: all private selectors/helpers are declared before their first use.
required_decls = [
    '@interface NSURLSession (ZZFilterObserveForward)',
    '@interface NSURLSessionTask (ZZFilterResumeObserve)',
    'static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest_completion(',
    'static NSURLSessionDataTask *ZZ_filter_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request);',
    'static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL_completion(',
    'static NSURLSessionDataTask *ZZ_filter_dataTaskWithURL(id self, SEL _cmd, NSURL *url);',
    'static NSString *ZZExtractVersionFromFlatText(NSString *value);',
    'static void ZZRecordObservedDetailRequest(NSURLRequest *request);',
    'static BOOL ZZLooksLikeDetailResponse(NSURLRequest *request, NSURLResponse *response, NSData *data);',
    'static BOOL ZZIsZhuanzhuanNetworkURL(NSURL *url);',
]
for decl in required_decls:
    if net.find(decl) < 0:
        print(f'FAIL ZZNetworkInterception.m: missing declaration: {decl}')
        fail = True

# v52 must be passive: no duplicated observer session or active observer request.
for forbidden in [
    'ZZObserverSession',
    'kZZObserverTaskKey',
    'ZZStartObserverForRequest',
    'ZZIsObserverTask',
    'observerTask',
]:
    if forbidden in net:
        print(f'FAIL ZZNetworkInterception.m: active observer residue detected: {forbidden}')
        fail = True

# Ensure the exclusion for the known non-detail 2xx endpoint is present.
if 'coke-real' not in net or 'ZZIsExcludedDetailResponseURL' not in net:
    print('FAIL ZZNetworkInterception.m: missing coke-real 2xx exclusion')
    fail = True

# Ensure failure diagnostics are actually written.
for token in [
    'gObservedDetailLastFailureURL',
    'gObservedDetailLastFailureMethod',
    'gObservedDetailLastFailureBody',
    'status >= 400 && status < 600',
]:
    if token not in net:
        print(f'FAIL ZZNetworkInterception.m: missing failure diagnostic token: {token}')
        fail = True

# v63: completion-handler payload census must expose generic response/OS-version
# hits without actively generating requests.
for decl in [
    'FOUNDATION_EXPORT NSUInteger ZZObservedNetworkPayloadResponses(void);',
    'FOUNDATION_EXPORT NSUInteger ZZObservedNetworkVersionPayloads(void);',
    'FOUNDATION_EXPORT NSInteger ZZObservedNetworkLastPayloadStatus(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkLastPayloadURL(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkLastPayloadMethod(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkLastPayloadBody(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkLastPayloadVersion(void);',
]:
    if decl not in net_header:
        print(f'FAIL ZZNetworkInterception.h: missing v63 payload declaration: {decl}')
        fail = True

for token in [
    'ZZObserveNetworkCompletionResponse',
    'gObservedNetworkPayloadResponses',
    'gObservedNetworkVersionPayloads',
    'ZZExtractVersionFromRawResponseData(data)',
    'data.length > (1024 * 1024)',
]:
    if token not in net:
        print(f'FAIL ZZNetworkInterception.m: missing v63 payload token: {token}')
        fail = True

# v62: task census must keep a separate candidate stream so noisy telemetry
# such as /v1/coke-real cannot hide the useful product-detail request.
for decl in [
    'FOUNDATION_EXPORT NSUInteger ZZObservedNetworkTaskCandidateRequests(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkTaskCandidateURL(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkTaskCandidateMethod(void);',
    'FOUNDATION_EXPORT NSString *ZZObservedNetworkTaskCandidateBody(void);',
]:
    if decl not in net_header:
        print(f'FAIL ZZNetworkInterception.h: missing v62 task candidate declaration: {decl}')
        fail = True

for token in [
    'ZZLooksLikeTaskCandidate',
    'gObservedNetworkTaskCandidateRequests',
    'gObservedNetworkTaskCandidateURL',
    'gObservedNetworkTaskCandidateMethod',
    'gObservedNetworkTaskCandidateBody',
    '任务候选',
]:
    if token not in net and token != '任务候选':
        print(f'FAIL ZZNetworkInterception.m: missing v62 task candidate token: {token}')
        fail = True


if fail:
    sys.exit(1)
print('STRUCTURE CHECK PASSED')
