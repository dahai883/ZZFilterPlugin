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
