# genesis_perception

The measurement domain, built on the [`genesis_tree`](https://pub.dev/packages/genesis_tree)
spine by subclassing (genesis ADR-0001 Decision 6). Pure Dart, bare VM.

A *measurement* is a read-only projection of the world: the model never
constructs perceptions directly — it observes, and its only write is a
hit-tested action after which the tree re-measures (the action half is
`genesis_consent`).

## Surface

- **`Perception extends Seed`** — a measurement node; `createElement()` is the
  domain factory.
- **`PerceptionElement extends Branch`** — reserved for artifact elements
  (`NodeElement`, `FieldElement`, custom measurement leaves); composition
  elements are thin subclasses of the tree composition branches that only
  upgrade the handle.
- **`PerceptionContext`** — a capability extension of `TreeContext` (adds
  `perceptionId` + `markNeedsHarvest`; inherits throw-after-unmount); the seam
  where the token budget lands.
- **`PerceptionOwner extends TreeOwner`** — `flushHarvest()` returns the
  rebuilt list.
- **`Node`** (named container, children widened to `List<Seed>`) and
  **`Field(String name, Object? value)`** (the non-generic leaf — a `Field<T>`
  would break `canUpdate` across value-type changes, and `null` is a legal
  measurement).

The tree spine is **re-exported in full**, so one import surfaces
`Seed`/`Branch`/`TreeContext`/`TreeOwner` and the composition layer
(`Watch`, `Sprout`, …) alongside the domain.

## Status

Pre-1.0; tracks `genesis_tree`. The measurement domain is stable in shape.
Design rationale: `docs/adr/ADR-0001-foundations.md` (Decision 6) in the
monorepo.

## License

[BSD-3-Clause](LICENSE).
