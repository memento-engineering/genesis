# Changelog

## 0.2.0

- **Breaking:** `debugFillProperties` now receives a `DiagnosticsBuilder` — replace `properties.add(...)` list calls with the builder `add()`; wire format unchanged.

## 0.1.2

- Docs only, no API changes: ship the LICENSE, CHANGELOG, and README that
  the 0.1.1 archive was published without.

## 0.1.1

Initial release.

- `Diagnosticable` and `DiagnosticableTree` — a dependency-free, pure-Dart
  diagnostics protocol. Implementers contribute their own properties via
  `debugFillProperties` and their own children via `debugDescribeChildren`, and
  get `toStringDeep()` for free. Types become diagnosable without any change to
  a central projector.
- `DiagnosticsProperty` — a sealed union over `string`, `int`, `double`, `flag`,
  `enumValue`, `duration`, `timestamp` and `object`, each carrying a
  `DiagnosticsLevel` (`fine` / `info` / `warning` / `error`) so severity travels
  with the value. Exhaustive switches are compiler-checked.
- `TreeSnapshot` / `TreeNode` — the typed, versioned wire contract for
  out-of-process consumers, carrying `contractVersion` and `projectedAt`. A
  deliberate divergence from Flutter, whose inspector ships an untyped
  `Map<String, Object?>`.

This package sits **below** `genesis_tree`, so a consumer that only reads
diagnostics depends on it alone and never pulls in a tree engine. It has no
runtime dependencies.

The diagnostics contract and snapshot types were previously developed as
`grid_diagnostics_contract` in the_grid, and briefly carried as
`genesis_diagnostics`; neither was ever published. Value types are hand-written
rather than generated, which is permanent for the foundation and the spine.
