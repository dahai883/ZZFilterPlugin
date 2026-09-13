# ZZFilterPlugin v29

独立实现的 iOS 商品列表“系统版本”筛选测试插件。v29 针对 **“详情响应已经有 36 条，但详情命中仍为 0”** 做了第二轮深入修复。

## v29 核心修复

- 详情响应增加严格的 HTTP 2xx 校验，并在状态面板显示 `详情响应（2xx / 失败）`，便于立即判断问题在请求还是解析。
- 新增独立的 `entryFromData:response:error:` 解析边界：JSON/text 两条路径统一处理。
- 支持多层 JSON 字符串包装、百分号编码后的 JSON，以及字符串形式的 `respData / report / params`。
- 对当前 JSON 对象做一次有限范围的序列化文本扫描，可识别 `"系统版本":"18.6.2"`、`{"key":"系统版本","value":"18.6.2"}` 等实际响应变体。
- `itemId2AttrInfo` 不再只接受字典值，也递归处理数组/字符串。
- 去掉详情请求头的窄白名单，改为参考实现思路的“复制源请求头 + 明确排除传输层头”，保留应用侧上下文头。
- 额外保留源列表请求的全部 query context，再补齐 `productId / infoId / strInfoId / uid / requestType / packageId / orderId / storeQrCode / searchFrom`。
- 保留 `jumpURL → moreInfo` 路径选择、Cookie 同步以及并发上限，避免再次出现高 CPU / 发热 / Watchdog。

## 测试重点

注入 v29 后先看状态：

`详情响应` 应与 `详情预取` 接近；`2xx` 表示服务器确实返回成功响应。若 2xx 已增加而 `详情命中` 仍为 0，下一步就能直接定位到响应内容本身，而不是继续盲猜网络请求。

## 编译

GitHub Actions 手动运行 `.github/workflows/build.yml`，目标 iOS 16+，arm64/arm64e。

本项目是独立过滤实现，不包含原插件的激活、授权校验、RSA 验签或绕过逻辑。
