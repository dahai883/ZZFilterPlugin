# ZZFilterPlugin — independent filter + overlay UI

这是一个独立重实现的 iOS dylib 示例，用于你自己的或明确授权的宿主 App 测试。

## 新增 ZZOverlayController

- 启动后在前台窗口显示一个小型“筛选”浮动按钮。
- 点击按钮打开设置面板。
- 可设置：启用/关闭、最小/最大数值、最低/最高版本。
- 支持拖动浮动按钮。
- 设置保存在 NSUserDefaults。
- 不包含第三方 App 激活码、许可证验证、RSA 签名绕过或其他授权绕过逻辑。

## 运行方式

宿主 App 应通过正常的动态库加载方式加载本 dylib，并自行调用 `ZZFilterMakeSessionConfiguration()` 后使用返回的 session configuration；网络协议不会自动替换宿主 App 未授权的网络栈。

## 架构

- iOS 16+
- arm64 + arm64e
- ARC
- Foundation / CoreFoundation / UIKit

## Debug

编译使用 `-DZZ_DEBUG=1 -g -O0 -fno-omit-frame-pointer`。`ZZOverlayController` 的按钮本身也可作为最直观的加载验证：如果在授权测试宿主中出现“筛选”按钮，说明 dylib 的初始化代码已经执行。
