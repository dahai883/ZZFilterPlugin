# ZZFilterPlugin v58

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
