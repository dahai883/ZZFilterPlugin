# ZZFilterPlugin v60

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
