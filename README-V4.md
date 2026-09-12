# ZZFilterPlugin V4

This build fixes the V3 runtime-hook failure caused by relying on `objc_msgForward`.
V4 uses typed Objective-C IMP blocks for the discovered list-rendering selectors and
only scans again when the runtime grows or while no hooks have been installed.

## Diagnostic meaning
- UI Hook > 0: runtime list entry points were found and wrapped.
- UI 调用 > 0: one of those wrapped methods has actually executed.
- 处理商品 / 隐藏商品: model filtering is running.
- 匹配目标方法: number of matching methods seen by the scanner.
- Hook失败: methods whose signature was rejected or could not be wrapped.
- 运行时扫描方法: methods inspected in the latest scan.

The network layer is retained as a separate diagnostic path. No activation,
license, or security-check bypass is included.
