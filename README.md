# ZZFilterPlugin v51

本版基于 v50 的实际测试结果继续修正。v50 已经观察到真实请求有 3 个 2xx 响应，其中最后状态 200、Content-Type 为 application/json，但实际版本解析仍为 0；同时大量请求返回 405。

## v51 重点
- 新增 NSURLSession 的 `dataTaskWithURL:` / `dataTaskWithURL:completionHandler:` 观察路径，避免只覆盖 request 形式而漏掉真实详情请求。
- 保留 GET / POST 表单 / POST JSON 三种受控请求统计。
- 诊断面板新增最后一个 2xx 响应的 URL 与 Body 预览，便于定位真实详情响应结构。
- 继续限制观察数量和递归深度，不恢复全局运行时扫描，避免历史高 CPU/内存问题。
- 加强源码结构检查：所有私有 selector/helper 在首次使用前声明；所有新增导出函数同时有 `.h` 声明和 `.m` 定义。

目标仍是独立的“系统版本”筛选与诊断，不修改转转账号、授权或安全机制。
