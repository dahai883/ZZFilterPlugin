# ZZFilterPlugin v23

This package is an independent overlay implementation for an authorized host app.

## What was changed after comparing the supplied reference dylib

The reference overlay has three important lifecycle characteristics visible in its Objective-C/Mach-O metadata:

1. `ZZOverlayController -start` registers for `UIApplicationDidBecomeActiveNotification` and immediately handles an already-active application.
2. `applicationDidBecomeActive:` defers the actual UI installation onto the main queue before calling `installButtonIfNeeded` and `refreshButton`.
3. `installButtonIfNeeded` searches the active window for a stable button tag before creating a new button, then adds the button directly to that window.

This debug revision follows those lifecycle ideas while keeping the implementation independent.

Additional diagnostics:

- `[ZZOverlay] CONSTRUCTOR CALLED`
- `[ZZOverlay] +load bootstrap main-queue callback`
- `[ZZOverlay] start called`
- application state / scene / window diagnostics
- `BUTTON INSTALLED` or `reusing tagged button`
- button tap diagnostics

The package does not modify activation/licensing/security checks of another product.


## GitHub Actions 一键编译

提交到 `main` 或在 GitHub 的 **Actions → Build ZZOverlayController Debug → Run workflow** 手动运行。

Workflow 会：

1. 使用 `macos-14` + Xcode/iPhoneOS SDK 编译；
2. 检查 Mach-O 是否同时包含 `arm64` 和 `arm64e`；
3. 检查 `ZZOverlayController`、`ZZOverlayBootstrap` 及公开过滤 API 符号；
4. 生成 SHA-256；
5. 同时上传单独的 `.dylib` Artifact 和完整 `ZZOverlayController-Debug.zip` Artifact。

运行成功后，在该次 Actions 运行页面底部的 **Artifacts** 下载即可。

## Reference-inspired network debugging

The reference binary contains an automatic `NSURLSessionConfiguration` interception layer in addition to its overlay. This build adds an independent, public-runtime implementation that automatically installs `ZZFilterURLProtocol` on the standard default/ephemeral session configurations. It also logs intercepted requests and whether a JSON product array was found and modified.

This is intended for debugging an authorized host/application integration; it does not implement activation, license, RSA, or authorization bypass logic.

## Reference-architecture update

The project now mirrors the **observable architecture** of the supplied reference binary: automatic `NSURLSessionConfiguration` interception, a `ZZProductVisibility` cache/model layer, and exported model/list filtering helpers (`ZZProductIDFromInfo`, `ZZShouldKeepModel`, `ZZFilteredModels`, `ZZFilterRenderedData`).

The implementation is an independent reimplementation and intentionally does not copy or implement the reference binary's activation, token, signature-verification, or licensing mechanisms.


### Xcode 15.x compatibility fix
`ZZProductFilter.m` now avoids dot-syntax `value.length` on a variable declared as `id`, which Xcode reports as `property 'length' not found on object of type '__strong id'`.

## Runtime listing adapter

This build adds an independent runtime adapter for known listing/model entry points when those classes and selectors are present at runtime. It filters model arrays before the host renders them and logs the selector, input count, output count, and hidden count. It does not copy implementation code from the reference binary.


## V23 稳定性与系统版本筛选

- 根据 V11/V12/V13 的崩溃、CPU resource 日志，彻底关闭全量 Objective-C runtime 扫描和 message-forwarding Hook；避免再次出现 `ZZCandidateScore` / runtime discovery 占用主线程导致 watchdog/resource 超限。
- 仅对转转搜索/商品详情相关 JSON 请求进行处理，不扫描 7 万+ Objective-C 类。
- 搜索列表商品通常不直接带“系统版本”，V23 会从列表提取商品 ID，并以低并发、短超时方式预取商品详情；从详情中的系统版本建立商品 ID→iOS 版本缓存。
- 已有缓存会直接用于列表响应过滤；详情服务较慢时最多等待约 1.2 秒，超时则原样放行，缓存供下一次刷新使用。
- 过滤范围只针对 iOS/系统版本，例如 `iOS 26.5 ～ iOS 26.6.1`。
- 保留“查看系统版本结果”诊断界面，方便确认哪些商品已经拿到版本信息。
- 不包含激活码、授权、RSA、签名校验或其他安全/许可绕过逻辑。
