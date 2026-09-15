# ZZFilterPlugin v36

独立实现的 iOS 商品列表“系统版本”筛选测试插件。

## v36 本轮修复

- 根据 v34 实测结果，详情接口当前返回 HTTP 405；因此本轮不再继续增加版本解析规则，而是优先修正详情请求方法。
- 详情请求同时从商品跳转 URL 与原始列表请求提取详情上下文参数，并补充 `strInfoId / infoid` 等可能出现的 ID 字段。
- 如果商品跳转 URL 本身就是可用的 HTTP(S) 详情链接，完整保留其原始 query 参数，再补齐缺失的 `productId`/详情上下文，避免丢掉服务端生成的 opaque 参数。
- 不再把搜索列表的全部 query 参数复制到详情请求，避免分页、排序、筛选等列表参数污染详情接口。若商品跳转 URL 本身携带 `infoId` 等参数，则优先保留。
- 详情请求保留原始应用层请求头（包括应用自己的上下文/签名字段），仅剔除 Host、Cookie、Content-Length、Connection 等由 URLSession 管理的传输头；Cookie 仍从当前 Cookie Storage 重新生成。
- 保留 HTTP 状态统计，并继续显示最后详情 HTTP 状态码，用于确认请求是否从 400 转为成功响应。
- 保留 v29-v31 已有的多层 JSON、文本、`itemId2AttrInfo`、系统版本字段解析能力。
- 继续限制详情并发，避免出现高 CPU、发热和 Watchdog 问题。

## 测试重点

注入 v36 后，先查看状态面板中的：

`详情预取 / 详情响应 / 2xx / 失败 / 最后HTTP状态 / 详情命中`

如果出现 `2xx > 0`，再重点观察 `详情命中` 是否增加；如果仍然 `2xx = 0`，最后 HTTP 状态码可以直接帮助判断服务端拒绝类型。

## 编译

GitHub Actions 手动运行 `.github/workflows/build.yml`，目标 iOS 16+，arm64/arm64e。



## v36 本轮修复
- 继续针对详情接口 405 做诊断与兼容处理。
- 状态面板新增详情请求方法计数：GET / POST 表单 / POST JSON。
- 详情调试日志记录 HTTP `Allow` 响应头，便于确认服务端实际允许的方法。
- 对 POST 再增加“URL 去 query、参数仅放 body”的表单与 JSON 两种变体。
- 对列表返回的同域 HTTP(S) 商品跳转 URL 放宽路径判断；如果转转使用不含 detail/item 关键词的短路径，也会优先尝试。
- 仍限制为最多 12 个商品、最多 5 种请求形状/商品，避免再次出现高 CPU / 发热问题。
