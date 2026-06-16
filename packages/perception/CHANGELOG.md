# Changelog

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
