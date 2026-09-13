# ZZFilterPlugin v27

独立的转转系统版本筛选测试插件；不包含激活码、授权或签名绕过逻辑。

## 本版关键修复
- 修复 v26：`ZZFindVersionDeep` 原来不处理 `NSArray`，而转转商品属性常见 `[{key,value}]` 数组结构，因此“详情命中 0”、范围筛选 0 条、结果标题没有 `iOS x.y.z`。
- 版本解析现在支持数组、`itemId2AttrInfo`、`respData/report`、嵌套 JSON 字符串。
- 识别成功后写入 `zzSystemVersion`，结果页、范围判断和标题统一读取规范化版本。
- 保留定点列表 Hook，不恢复 v11 的全量 Runtime 扫描，避免高 CPU/发热/Watchdog。
- 标题继续显示 `iOS x.y.z`，并去除显示层“钛金属”“全网通”。

## 编译
GitHub Actions：iOS 16+，arm64 / arm64e。

## 建议测试
1. 不设置范围：结果页应出现 `｜ iOS x.y.z`。
2. 设置 `18.0.0 ~ 27.0.0`：结果不应再固定为 0 条。
3. 状态中的“详情命中”应大于 0。
4. 观察 CPU、发热和稳定性。
