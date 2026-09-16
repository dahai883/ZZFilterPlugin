# ZZFilterPlugin v44

独立的系统版本筛选与详情数据增强测试版本。

本版重点：不再只依赖 `NSURLSession` 的 dataTask 创建方法观察详情请求，而是额外在 `NSURLSessionTask resume` 边界检查实际任务的 originalRequest/currentRequest。仅对同域、疑似详情请求进行有限观察，并对观察任务做关联标记，避免递归。

诊断新增：
- `详情观察`：实际观察到的疑似详情任务数量；
- 调试日志记录实际 method / URL / productId；
- 保留 v42 的 24 个观察任务上限与受限详情预取。

编译前会先通过源码结构检查，确保私有 category 方法、static helper 均已在首次使用前声明；同时打包前会清理 `__pycache__`、`.pyc` 等 Python 缓存，并运行源码结构检查。

本项目为独立的授权测试/筛选实现，不修改激活、授权、签名或许可状态。


v44 编译稳定性修正：把 NSURLSession/NSURLSessionTask 私有 category 声明及 ZZObserverSession 等 static helper 原型统一前置到首次使用之前，并把该规则加入源码结构检查，避免 v43 的隐式声明/重复 static 声明错误再次出现。
