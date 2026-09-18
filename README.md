# ZZFilterPlugin v46

Independent iOS system-version filtering plugin for authorized on-device testing.

v46 focuses on the real detail responses observed from the host app. When the
host app returns a successful detail response, the plugin performs a bounded
multi-pass association between product IDs and the system-version attribute,
including `itemId2AttrInfo` map responses where the product ID can be the map key.

It keeps the existing diagnostic counters and avoids global runtime enumeration.
Source checks are included to catch declaration-order, missing-selector, malformed
Objective-C literal, and implementation-structure regressions before CI builds.
