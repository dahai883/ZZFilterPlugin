from pathlib import Path
import re, sys

root = Path(__file__).resolve().parent
fail = False
for p in root.glob('*.m'):
    text = p.read_text(errors='replace')
    # Basic directive balance. This is intentionally conservative: it catches
    # premature/missing @end mistakes without pretending to be a full compiler.
    impls = len(re.findall(r'^\s*@implementation\b', text, re.M))
    ends = len(re.findall(r'^\s*@end\s*$', text, re.M))
    if p.name == 'ZZOverlayController.m':
        if impls != 3 or ends != 6:
            print(f'FAIL {p.name}: expected 3 implementations / 6 @end, got {impls}/{ends}')
            fail = True
        s = text
        outer_end = s.find('\n@end', s.find('@implementation ZZOverlayController'))
        results_impl = s.find('@implementation ZZVersionResultsController')
        show = s.find('- (void)showVersionResultsFrom:')
        present = s.find('- (void)presentSettingsFrom:')
        refresh = s.find('- (void)refreshButton')
        cell_iface = s.find('@interface ZZVersionResultCell')
        if not (outer_end >= 0 and show >= 0 and present >= 0 and refresh >= 0 and show < outer_end and present < outer_end and refresh < outer_end and results_impl > outer_end and cell_iface > outer_end):
            print('FAIL ZZOverlayController.m: outer controller methods are not inside the outer implementation')
            fail = True
    print(f'CHECK {p.name}: implementations={impls}, @end={ends}')

# Cross-file declaration sanity checks for class singleton calls. This catches the
# exact v25 failure ([ZZDetailFetcher shared]) before GitHub Actions does.
headers = "\n".join(x.read_text(errors="replace") for x in root.glob("*.h"))
impl_text = "\n".join(x.read_text(errors="replace") for x in root.glob("*.m"))
for cls in ["ZZDetailFetcher", "ZZProductVisibility", "ZZSettings", "ZZOverlayController"]:
    if f"[{cls} shared]" in impl_text and f"+ (instancetype)shared;" not in headers and f"+ (id)shared;" not in headers:
        print(f"FAIL missing +shared declaration for {cls}")
        fail = True
if '@["' in impl_text:
    print("FAIL malformed Objective-C array literal token @[\" detected")
    fail = True

if fail:
    sys.exit(1)
print('STRUCTURE CHECK PASSED')
