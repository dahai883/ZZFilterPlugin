# ZZFilterPlugin v28

独立实现的 iOS 商品列表“系统版本”筛选测试插件。v28 重点修复 **详情预取有请求但详情命中始终为 0、结果列表无法显示 iOS 版本** 的问题。

## v28 改动

- 深化系统版本解析：支持 `系统版本 / iOS版本 / systemVersion / iosVersion` 等字段。
- 支持 `params / attrs / attributes / detail / respData / report / itemId2AttrInfo` 的嵌套数组/字典。
- 支持 `{key:"系统版本", value:"18.6.2"}` 这类没有 `iOS` 前缀的数据。
- 支持从扁平文本中恢复 `iOS 18.6.2`、`系统版本：18.6.2`。
- 详情接口返回非 JSON 文本时也尝试提取系统版本。
- 状态窗口新增“详情响应”，用于区分“请求没返回”和“返回了但解析不到版本”。
- 继续避免全量 Runtime 扫描，避免 v11 的高 CPU/发热/Watchdog 问题。
- 结果列表保留 `iOS x.y.z`、复制/打开和标题清理功能。

## 编译

GitHub Actions 手动运行 `.github/workflows/build.yml`，目标 iOS 16+，arm64/arm64e。

本项目是独立过滤实现，不包含原插件的激活、授权校验、RSA 验签或绕过逻辑。
