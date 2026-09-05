# Changelog

## 0.1.2

- `DialogueSurface.apply` verifies root compatibility itself and **release builds now enforce** it: a message whose root component id resolves to a different component type throws `StateError` before the mounted tree is touched, instead of relying on a stripped assertion. Surface metadata (`surfaceId`) is committed only after the root update succeeds, so a failed apply no longer leaves the surface describing a message its tree never took. No API change.

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev; no API changes.

## 0.1.0

- Initial release: the A2UI v0.9 wire — the updateComponents codec, the receive-side DialogueSurface (reconcile by key), and action-message parsing.

  Pre-1.0 and experimental; APIs may change before 1.0.
