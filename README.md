# ZZOverlayController-Debug (reference-informed)

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
