# ZZFilterPlugin v47

Independent iOS system-version filtering plugin for authorized on-device testing.

v47 continues from the first successful real-detail 2xx observations. It adds
a whole-response version scan for opaque attribute keys, response-URL product-ID
recovery, and a bounded response-level ID/version association when exactly one
product ID is present. Diagnostics now expose actual version parses.

The implementation keeps bounded traversal and avoids global runtime enumeration.
Source checks remain enabled for Objective-C declaration order, selector
declarations, literals, and implementation structure before CI builds.
