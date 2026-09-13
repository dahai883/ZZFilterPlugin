# ZZFilterPlugin v19

## v18 build-error fix
- The result-controller type is declared before `ZZOverlayController` uses it.
- `showVersionResultsFrom:`, `presentSettingsFrom:`, and `refreshButton` remain inside `@implementation ZZOverlayController`.
- The `ZZVersionResultCell` and `ZZVersionResultsController` helper implementation blocks remain outside the main controller implementation.
- `sender.tag` bounds checks use an explicit `NSUInteger` cast.

## Build hygiene
- `verify-source-structure.py` checks implementation/end structure and verifies that the main controller methods occur before its closing `@end`.
- The package is intended to be compiled by the existing GitHub Actions workflow.

## Stability
- Keeps the performance-safe network/detail filtering path.
- Does not restore global runtime enumeration or high-frequency UI scanning.
