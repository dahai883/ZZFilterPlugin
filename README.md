# ZZFilterPlugin v40

独立的系统版本筛选与网络详情数据增强测试版本。

v37 针对 v36 中详情请求全部返回 HTTP 405 的情况，增加：
- 从列表请求的 URL、HTTP Body、`zzreqallparam` 提取受限的详情上下文字段；
- 保留参考实现中观察到的 `/zzopen/waresshow/moreInfo`、`/zzopen/waresshow/moreinfo`、`/waresshow/moreinfo` 三种路径形态；
- 先尝试备用 GET 路径，再按 400/405 触发 POST 表单/JSON 以及 Body-only 变体；
- 记录实际请求方法、HTTP 状态、`Allow` 响应头和响应体预览；
- 详情请求仍限制为每批最多 12 个商品、并发 3，避免高 CPU/发热。

本版本不修改激活、授权、签名或许可状态。


v40: 增加对转转 App 自身详情请求的只读监听与版本缓存；详情页原始响应不改写。


### v40
在不修改转转原始详情响应的前提下，额外观察 NSURLSession 实际发出的同域详情请求，并使用原请求的 URL、Header、HTTPBody 原样复制一个只读观察请求；成功 2xx JSON 响应会尝试提取商品系统版本并写入缓存。观察请求有数量上限，避免造成额外网络/CPU 压力。
