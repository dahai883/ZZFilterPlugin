# ZZFilterPlugin Diagnostic Build

This build adds an on-device diagnostic display to the independent filter plugin.

## On-device status
- The floating button updates once per second.
- `✓ UI:n` means n runtime list entry points were detected and hooked.
- `! UI:0` means no known runtime list entry point was found in the current app build.
- `隐:n` is the number of model objects rejected by the independent visibility filter so far.

## Detailed diagnostics
Long-press the floating button for:
- UI Hook count
- UI filtering calls
- processed model count
- hidden model count
- intercepted network request count
- modified response count

This is intended for debugging an authorized host/application integration.

## Dynamic runtime discovery
This diagnostic build no longer depends on two hard-coded controller class names. It scans the running authorized host for the known list-rendering selectors and reports discovered/hooked counts. This helps distinguish a class-name mismatch from a real absence of the list-rendering API.

## 2026-09-12 reference-informed UI hook revision

The supplied `zz_0.0(2).dylib` was inspected at the Objective-C/Mach-O metadata level. The revision expands runtime discovery to the complete selector inventory observed in its listing-rendering layer, including singular cell insertion, batch cell insertion, listing reload/add, page requests, and page-index setters.

Observed selector names used only as interoperability targets:
- `addCellWithModel:forSection:className:`
- `addCellWithModel:forSection:className:tag:`
- `addCellsWithModelArray:forSection:className:`
- `addCellsWithModelArray:forSection:className:tag:`
- `insertCellsWithModelArray:forSection:className:pos:`
- `insertCellsWithModelArray:forSection:className:tag:pos:`
- `p_addCellsWithModelArray:forSection:className:tag:`
- `p_insertCellsWithModelArray:forSection:className:tag:pos:`
- `reloadListingGoodsWithRespModel:`
- `addListingGoodsWithRespModel:`
- `requestDataWithPageIndex:`
- `setPageIndex:`

The revision remains activation-free: it does not reproduce or bypass token, RSA, signature, licensing, or authorization checks from the reference binary.

The build environment is macOS/Xcode via GitHub Actions. This container does not include Apple's iPhoneOS SDK, so the archive contains the updated source/workflow rather than a newly compiled iOS dylib.
