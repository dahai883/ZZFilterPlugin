# ZZFilterPlugin v17

修复 v15 系统版本识别错误。

## 核心修复
- v15 把商品/模型通用 `version=1.0.0` 当成 iOS 系统版本。
- v17 优先识别 `iosVersion`、`systemVersion`、`ios` 等系统字段。
- 支持转转常见的 `{key:"系统版本", value:"iOS 26.4.1"}` 属性结构。
- 支持 `itemId2AttrInfo` 这类“商品 ID 作为字典 key”的详情结构，并补回 productId。
- 通用 `version/modelVersion/goodsVersion/waresVersion` 只有在值明确带 `iOS` 时才接受。
- 保持 v14/v15 的稳定性策略：不恢复全局 Runtime 扫描。

## 预期
“查看系统版本结果”不应再显示整批 `iOS 1.0.0`。如果详情 payload 中真实存在系统版本，应显示类似 `iOS 26.4.1`。
