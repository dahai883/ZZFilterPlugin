# ZZFilterPlugin v32

独立实现的 iOS 商品列表“系统版本”筛选测试插件。

## v32 本轮修复

- 根据 v30/v31 实测结果，确认详情请求能够收到 HTTP 响应，但全部不是 2xx；因此本轮重点修正“详情请求形状”，不再继续盲目增加解析规则。
- 详情请求的 query 参数改为参考路径的最小集合：`productId` + `uid / previewToken / infoId / platform / requestType / packageId / t / ip / token / orderId / doubleTrackFineness / source / storeQrCode / searchFrom / quickStart`。
- 不再把搜索列表的全部 query 参数复制到详情请求，避免分页、排序、筛选等列表参数污染详情接口。
- 详情请求的源请求头复制边界进一步收紧，排除 Cookie、Host、Content-Type、Origin、Referer 以及传输/请求上下文相关头；Cookie 和 Referer 按当前详情 URL/源请求重新设置。
- 保留 HTTP 状态统计，并新增“最后详情 HTTP 状态码”，用于区分 400/401/403/404/5xx 等服务端返回。
- 保留 v29-v31 已有的多层 JSON、文本、`itemId2AttrInfo`、系统版本字段解析能力。
- 继续限制详情并发，避免出现高 CPU、发热和 Watchdog 问题。

## 测试重点

注入 v32 后，先查看状态面板中的：

`详情预取 / 详情响应 / 2xx / 失败 / 最后HTTP状态 / 详情命中`

如果出现 `2xx > 0`，再重点观察 `详情命中` 是否增加；如果仍然 `2xx = 0`，最后 HTTP 状态码可以直接帮助判断服务端拒绝类型。

## 编译

GitHub Actions 手动运行 `.github/workflows/build.yml`，目标 iOS 16+，arm64/arm64e。
