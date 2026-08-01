# Changelog

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
