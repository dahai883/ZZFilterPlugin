# ZZFilterPlugin v15

基于 v14 的编译修正版。

修复：
- `ZZOverlayController.m` 使用 `ZZProductVersionFromDictionary` 时缺少 `ZZProductFilter.h` 声明，导致 `undeclared function`、ARC 下 `int` 到 `NSString *` 的连锁编译错误。
- 补充头文件导入后，函数按 `NSString *` 正确声明。

说明：
- 保留 v14 的稳定性策略：不做全局 Runtime 扫描/消息转发 Hook。
- 系统版本筛选仍走列表响应 + 商品详情缓存。
- 仅修复编译问题，没有加入激活码/授权绕过逻辑。
