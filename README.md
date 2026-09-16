# ZZFilterPlugin v43

独立的系统版本筛选与详情数据增强测试版本。

本版重点：不再只依赖 `NSURLSession` 的 dataTask 创建方法观察详情请求，而是额外在 `NSURLSessionTask resume` 边界检查实际任务的 originalRequest/currentRequest。仅对同域、疑似详情请求进行有限观察，并对观察任务做关联标记，避免递归。

诊断新增：
- `详情观察`：实际观察到的疑似详情任务数量；
- 调试日志记录实际 method / URL / productId；
- 保留 v42 的 24 个观察任务上限与受限详情预取。

打包前会清理 `__pycache__`、`.pyc` 等 Python 缓存，并运行源码结构检查。

本项目为独立的授权测试/筛选实现，不修改激活、授权、签名或许可状态。
