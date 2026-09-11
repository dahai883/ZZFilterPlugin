# ZZFilterPlugin

这是一个**独立实现**的 iOS 商品列表过滤 dylib 源码示例，目标是提供可审计、可修改的过滤逻辑。

## 功能

- 开关过滤
- 数值范围过滤
- 版本范围过滤
- 对 JSON 中常见的 `items` / `data` / `list` / `results` 数组进行过滤
- 提供 `NSURLProtocol` 组件，可由**有权修改的宿主 App**显式加入自己的 `NSURLSessionConfiguration`
- 不包含原插件的激活、授权校验、RSA 验签或绕过逻辑

## 编译环境

使用 GitHub Actions 的 macOS runner + Xcode/iPhoneOS SDK。

本项目要求：
- iOS 16.0+
- arm64 / arm64e
- Objective-C ARC

## GitHub Actions

仓库中的 `.github/workflows/build.yml` 会在手动触发后使用 macOS runner 编译。

## 宿主 App 接入

公开入口：

```objc
NSURLSessionConfiguration *cfg = ZZFilterMakeSessionConfiguration();
NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
```

或者：

```objc
[ZZFilterURLProtocol installOnSessionConfiguration:cfg];
```

然后按需要设置：

```objc
ZZFilterSetEnabled(YES);
ZZFilterSetTextRange(100, 10000);
ZZFilterSetVersionRange(@"2.0", @"5.0");
```

## 数据格式

过滤器会优先寻找这些数组字段：

- `items`
- `data`
- `list`
- `results`

数组元素如果包含 `id`、`productId`、`goodsId`、`title` 或 `name` 等字段，会被作为候选商品对象。

### 注意

真实 App 的接口 JSON 字段如果不同，需要根据你有权测试的 App 的实际数据结构调整解析器。不要把本项目用于绕过第三方 App 的授权、访问控制或安全机制。
