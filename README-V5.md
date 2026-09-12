# ZZFilterPlugin V5

V5 is a diagnostic-oriented continuation of V4 for authorized testing.

Changes:
- Keeps the working typed-IMP runtime hooks from V4.
- Adds response-object diagnostics so `addListingGoodsWithRespModel:` and `reloadListingGoodsWithRespModel:` report the concrete response class.
- Adds KVC-based handling for common list properties (`items`, `infos`, `goods`, `products`, `data`, etc.) when the response is a model object rather than an NSDictionary.
- Adds deeper response-envelope handling for dictionary payloads.
- Adds counters for response object types and models that cannot be converted to a dictionary.
- Runtime discovery is retriggered on app activation and more frequently during startup.

This does not include activation/license/security-check bypassing.
