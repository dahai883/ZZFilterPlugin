# ZZFilterPlugin v64

## v58 透明观察诊断版
- 保留 v56 的被动观察策略和紧凑状态栏。
- 新增“观察 2xx”独立统计：区分“App 实际返回的任意 2xx”和“通过详情候选判定的 2xx”。
- 新增最后一个实际观察到的 2xx URL / Method / Body / Content-Type / 字节数诊断数据。
- 详情候选判断同时参考 request URL 与 response URL，避免重定向或响应 URL 改变后被错误排除。
- 状态栏增加 `观察2xx：N / 候选2xx：N`，若存在实际 2xx 同时显示其紧凑 URL。
- 完整 Body 继续只写 Debug 日志，避免弹窗过长。
- 不增加新的主动网络请求。

## 本版测试重点
如果 `观察2xx` > 0 但 `候选2xx` 仍为 0，状态栏会直接显示最后一个实际 2xx URL；据此可继续定位真正的详情接口。

当前环境未提供 iPhoneOS SDK，因此最终 arm64/arm64e 编译仍需通过 GitHub Actions 完成。


## v59 changes
- Passive detail capture: speculative detail prefetch is disabled to avoid synthetic 405 traffic.
- Added direct capture for `/u/streamline_detail/new-goods-detail`, including POST/body requests.
- Added protocol-level detail request/response counters and last status diagnostics.
- Known `/v1/coke-real` 2xx remains excluded from detail candidates.
- Debug popup remains compact; full URL/body stays in the debug log.


## v60 changes
- Keep v59 passive-only behavior: no synthetic detail requests and no new active probes.
- Add direct diagnostics for the last observed detail request URL / method / body.
- Show the last observed 2xx URL and body summary in the status popup so the actual network path can be identified without relying on an external log viewer.
- Keep `/v1/coke-real` excluded from detail candidates.
- No filtering rule is changed in this diagnostic step; the goal is to identify the real detail data path before parsing system version.
- Source structure checks must pass before packaging.

## v60 test focus
Open the same product detail page and open the ZZFilterPlugin status. The important fields are `观察最后`, `2xx最后`, `2xx摘要`, and `协议详情`. If the 2xx URL is not the real product-detail endpoint, the next version can target the exact transport/path instead of generating more 405 requests.


## v61 changes
- Keep the v60 passive-only diagnostic strategy; no synthetic detail requests are added.
- Add a lightweight `NSURLSessionTask resume` network census for Zhuanzhuan-host requests.
- Record the latest task URL, HTTP method, and short request body preview even when the endpoint does not look like a conventional `detail/goods/item` path.
- This is specifically to locate opaque detail endpoints that v60 could not classify; `/v1/coke-real` remains excluded from detail candidates.
- Status popup adds `任务观察 / 任务最后 / 任务Body` while keeping the existing detail and protocol counters.
- No filtering behavior is changed in this diagnostic version.

## v61 test focus
Open the product detail page, refresh the ZZFilterPlugin status, and check `任务最后`. If it is not `coke-real`, its path/body can be used to identify the actual product-detail transport.


## v63
- 继续保持被动模式，不主动生成详情请求。
- 在 NSURLSession completionHandler 路径增加受限的转转响应普查。
- 对 <=1MB 的候选/含系统版本响应提取 iOS 版本，并尝试关联商品 ID。
- 明确排除 /v1/coke-real，避免无关 2xx 覆盖诊断。
- 状态框新增“网络响应 / 版本载荷 / 载荷最后 / 载荷版本 / 载荷摘要”。


## v64 changes
- 修复 v63 GitHub Actions 编译错误：`ZZIsZhuanzhuanNetworkURL` 在首次调用前缺少静态函数前置声明。
- 保持函数定义为 `static`，并在首次使用前显式声明，避免 Clang 的 `-Wimplicit-function-declaration` 与 `static declaration follows non-static declaration`。
- 强化源码结构检查：要求该内部函数的前置声明存在。
- 不改变 v63 的被动网络响应普查和系统版本载荷扫描逻辑。
- 不增加主动网络请求。

## v64 test focus
本版首先用于确认 Actions 能完整编译通过。编译成功后再注入转转，继续观察 v63 的“网络响应 / 版本载荷”诊断结果。

## v65 changes
- 修正 v64 的核心诊断缺口：`网络响应 0` 说明仅靠 completionHandler 路径无法覆盖转转使用的自定义 `NSURLSession` delegate 数据流。
- 新增被动 delegate 数据流观察：在 App 创建带 delegate 的 NSURLSession 时，对该 delegate 的 `URLSession:dataTask:didReceiveData:` 与 `URLSession:task:didCompleteWithError:` 做最小化运行时包装。
- 对每个 data task 最多累计 1MB 响应数据，任务完成后复用现有版本载荷扫描逻辑；不主动创建请求、不修改响应内容。
- 保留 `/v1/coke-real` 排除及现有候选 URL 逻辑。
- 所有内部 helper/selector 均提前声明，继续强化 Clang 静态兼容性检查。


## v66 changes
- Analyzed the supplied SpiderProxy HAR archive: it contains HTTPS CONNECT tunnel metadata only, so it exposes destination hosts but not decrypted HTTP paths, request bodies, or response bodies.
- Useful hosts observed in the capture include `app.zhuanzhuan.com`, `m.zhuanzhuan.com`, `v4.zhuanzhuan.com`, `v6.zhuanzhuan.com`, `lego.zhuanzhuan.com`, and `lego-tech.zhuanzhuan.com`; monitoring/telemetry hosts are kept as non-detail noise.
- Added passive `NSURLSession` upload-task completion observation for `uploadTaskWithRequest:fromData:completionHandler:` and `fromFile:completionHandler:` because POST traffic may use upload tasks rather than data-task completion handlers.
- Added passive delegate response-header observation for `URLSession:dataTask:didReceiveResponse:completionHandler:` and resets the per-task response buffer on a new response/redirect.
- Existing delegate data accumulation and completion parsing remain passive and response-transparent.
- Task census debug now records the request host explicitly, making it possible to map the app's observed candidate endpoint to the hosts seen in the proxy capture.
- No active network probes and no response mutation were added.
