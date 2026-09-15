# ZZFilterPlugin v37

独立的系统版本筛选与网络详情数据增强测试版本。

v37 针对 v36 中详情请求全部返回 HTTP 405 的情况，增加：
- 从列表请求的 URL、HTTP Body、`zzreqallparam` 提取受限的详情上下文字段；
- 保留参考实现中观察到的 `/zzopen/waresshow/moreInfo`、`/zzopen/waresshow/moreinfo`、`/waresshow/moreinfo` 三种路径形态；
- 先尝试备用 GET 路径，再按 400/405 触发 POST 表单/JSON 以及 Body-only 变体；
- 记录实际请求方法、HTTP 状态、`Allow` 响应头和响应体预览；
- 详情请求仍限制为每批最多 12 个商品、并发 3，避免高 CPU/发热。

本版本不修改激活、授权、签名或许可状态。
