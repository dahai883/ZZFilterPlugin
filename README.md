# ZZFilterPlugin v25

独立的转转系统版本筛选测试插件。v25 基于此前测试结果与用户提供的成功版本做了针对性修正，不包含激活码、授权或签名绕过逻辑。

## v25 重点

本版重点不是改状态窗口，而是修复 v23/v24 实测暴露的“详情命中 0、范围筛选 0 条、结果固定 20 条、标题无系统版本”问题。
- 针对转转已知列表入口做定点 UI 过滤，不进行全量 Objective-C runtime 扫描。
- 参考成功版本的 `ZZListingAprilViewController` / `ZZFlexibleLayoutViewController` 列表方法入口。
- 详情预取同时使用商品列表中的 `jumpUrl/detailUrl` 信息，并保留必要请求头与 Cookie。
- 继续解析 `系统版本`、`iOSVersion`、`systemVersion`、`itemId2AttrInfo` 等字段。
- 兼容详情响应中嵌套 JSON 字符串。
- 结果页支持继续请求后续列表页，不再把结果设计成固定 20 条。
- 商品标题显示 `iOS x.y.z`；显示名称继续去除 `钛金属`、`全网通`。
- 保留复制 / 打开商品链接。
- 状态页保留完整统计、刷新、重置统计、关闭；移除无意义的 V14 说明文字。

## 编译
GitHub Actions 使用仓库现有 workflow 编译 `ZZFilterPlugin.dylib`，目标 iOS 16+，arm64 / arm64e。

## 测试重点
1. 设置 `18.0.0 ~ 26.6.1` 后观察是否出现匹配商品。
2. 查看状态中的“详情命中”是否从 0 变成有效数量。
3. 打开“查看系统版本结果”，确认标题带 `iOS x.y.z`。
4. 向下加载列表后再次打开结果页，确认数量可以超过 20。
5. 观察注入后的 CPU、发热和稳定性。
