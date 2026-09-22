# Changelog

## 0.4.0-dev.1
- **Breaking:** perception now surfaces the canonical tree spine: migrate tree-facing `Seed`/`Branch`/`TreeContext`/`TreeOwner` signatures to `Component`/`Element`/`BuildContext`/`BuildOwner`, including `component`, `elementId`, and inherited-value lookup members. `Perception`, `Node`, `Field`, harvest names, and the version-1 `seedType` wire key remain unchanged.

## 0.3.1

- Require `genesis_tree ^0.4.0`: the published pin moves off the 0.3.x line so consumers that
  adopted genesis_tree 0.4.0 (grid_engine 0.4.0-dev.1 and up) can resolve perception beside it.
  No perception-side API change; a caret consumer on `genesis_perception ^0.3.0` picks this up
  automatically, and one still on genesis_tree 0.3.x keeps resolving 0.3.0.

## 0.3.0

- **Breaking:** `PerceptionContext` carries the tree handle's aspect-scoped dependency, so `dependOnInheritedSeedOfExactType<T>()` now takes an optional `{Object? aspect}`. Migration: an external `PerceptionContext` implementation adds `{Object? aspect}` to that method and forwards it to the handle it wraps. Call sites that pass no aspect are unchanged.
- Require `genesis_tree ^0.3.0`: `InheritedModelSeed` and the aspect-scoped dependency reach perception through its full tree re-export, with no perception-side code change.

## 0.2.0

- **Breaking:** `debugFillProperties` now receives a `DiagnosticsBuilder` — replace `properties.add(...)` list calls with the builder `add()`; wire format unchanged.

## 0.1.4

- Retarget typed tree projection to `genesis_foundation ^0.1.1` and require
  `genesis_tree ^0.1.6`; foundation diagnostics remain available through
  perception's full tree re-export.

## 0.1.3

- `PerceptionContext` gains `getInheritedSeedOfExactType<T>()` via its
  `TreeContext` base — the dependency-free inherited lookup for one-shot
  reads (e.g. from `initState`); the domain handle delegates it to the
  wrapped tree handle. Requires `genesis_tree` `^0.1.4`.

## 0.1.2

- Add `serializePerceptionFragment(Branch)` — harvests a mounted `Node`/`Field`
  subtree into a nested JSON map (a `Field` becomes `name: value`, a child
  `Node` becomes `name: { … }`). The one place a measurement crosses to the
  wire.

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev; no API changes.

## 0.1.0

- Initial release: the measurement domain on the tree spine — Perception/PerceptionContext/PerceptionOwner, Node/Field, the harvest pipeline.

  Pre-1.0 and experimental; APIs may change before 1.0.
