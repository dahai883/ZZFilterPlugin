# ZZFilterPlugin v8

V8 is a crash-stability revision of the independent runtime filtering experiment.

Changes from v7:
- No inherited-method promotion via `class_addMethod`.
- Only class-declared list-rendering selectors are considered.
- `requestDataWithPageIndex:` is not hooked because its signature is not a model-array API.
- Only void-returning candidate methods are hooked.
- Runtime diagnostics remain available in the status panel.

This build does not alter activation/licensing/security checks of the host app.
