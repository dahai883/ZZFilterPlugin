# ZZFilterPlugin v48

Independent iOS system-version filtering plugin for authorized on-device testing.

v48 continues from the first successful real-detail 2xx observations. It adds
a whole-response version scan for opaque attribute keys, response-URL product-ID
recovery, and a bounded response-level ID/version association when exactly one
product ID is present. Diagnostics now expose actual version parses.

The implementation keeps bounded traversal and avoids global runtime enumeration.
Source checks remain enabled for Objective-C declaration order, selector
declarations, literals, and implementation structure before CI builds.


## v48 compile fix
- Fixes an undeclared-function call in `ZZNetworkInterception.m`.
- Uses a locally declared/defined response-text parser so Objective-C ARC does not infer an `int` return type.
- Adds a source-structure guard for this class of missing static helper declarations.
