# ZZFilterPlugin v56

## v56 重点
- 保留 v55 的单屏 Debug 状态栏。
- 插件主动发出的详情探测请求增加 `X-ZZFilter-Internal-Detail: 1` 标记。
- 被动详情观察器完全忽略插件自己的探测请求，避免把 405/重试统计成转转 App 的真实流量。
- 详情预取改为每个商品只尝试一次 GET，不再连续尝试多个 POST/备用路径。
- 目标是先获得转转 App 自己的真实详情请求/2xx 响应，再从真实响应关联系统版本。
- 完整 URL/Body 仍写入 Debug 日志，状态栏只保留摘要。

## 注意
当前构建环境未提供 iPhoneOS SDK，因此需通过 GitHub Actions 在目标 SDK 下完成最终 arm64/arm64e 编译。
