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

## 设备端文件诊断
本诊断版额外写入 `/tmp/ZZFilterPlugin-diagnostic.log`，不依赖 iOS 上不存在的 `log show`、`vmmap`、`strings` 命令。

复现一次后执行：
```
cat /tmp/ZZFilterPlugin-diagnostic.log
```
如果文件存在，直接把全部内容发回来即可。
