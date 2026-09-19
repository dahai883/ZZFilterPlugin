# ZZFilterPlugin v50

Independent iOS system-version filtering plugin for authorized on-device testing.

v50 continues from the first successful real-detail 2xx observations. It adds
a whole-response version scan for opaque attribute keys, response-URL product-ID
recovery, and a bounded response-level ID/version association when exactly one
product ID is present. Diagnostics now expose actual version parses.

The implementation keeps bounded traversal and avoids global runtime enumeration.
Source checks remain enabled for Objective-C declaration order, selector
declarations, literals, and implementation structure before CI builds.


## v50 compile fix
- Fixes an undeclared-function call in `ZZNetworkInterception.m`.
- Uses a locally declared/defined response-text parser so Objective-C ARC does not infer an `int` return type.
- Adds a source-structure guard for this class of missing static helper declarations.


## v50

针对 v48：实际详情响应存在 2xx，但实际版本解析仍为 0。v50 增加原始 2xx 响应的 UTF-8/UTF-16 版本扫描，并在状态面板显示最后一个 2xx 的版本、字节数和 Content-Type；若解析到版本且能取得商品 ID，会直接建立商品-系统版本关联。


## v50
- Fixed linker errors for the v49 diagnostic exports: ZZObservedDetailLast2xxVersion/Bytes/ContentType are now defined in ZZNetworkInterception.m and exported in the header.
- Added a source-level regression check for exported diagnostic declarations/definitions so these symbols cannot be referenced without a definition in future versions.
- The unused helper warning is non-fatal and does not block linking.
