# ZZFilterPlugin v45

独立的系统版本筛选与详情数据增强测试版本。

本版重点：不再只依赖插件主动构造的详情请求。对宿主 App 自己通过 `NSURLSession dataTaskWithRequest:completionHandler:` 返回的疑似详情响应增加“实际响应观察”，优先从 App 已经成功拿到的数据中学习系统版本。

诊断新增：
- 实际详情响应：宿主 App 真实完成回调的详情响应数量；
- 实际最后状态：宿主 App 真实详情响应的 HTTP 状态；
- Allow：真实响应的 Allow 头；
- 调试日志记录真实 method / URL / productId / status / Content-Type / body 预览。

插件自身的有限详情预取仍保留，用于兼容没有走 completion-handler 的场景。观察请求使用专用标记，避免插件自己的观察请求被重复统计。

编译前继续执行源码结构检查，避免 v43 一类的声明顺序、私有 selector 可见性和 singleton 声明问题。

本项目为独立的授权测试/筛选实现，不修改激活、授权、签名或许可状态。
