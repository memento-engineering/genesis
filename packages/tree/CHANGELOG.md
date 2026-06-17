# Changelog

## 0.1.3

- Add `MultiChildSeed`/`MultiChildBranch` to the (experimental) composition
  layer: a config-declared multi-child container that keyed-reconciles its
  `List<Seed> children` via `Branch.updateChildren` — the
  `MultiChildRenderObjectElement` analogue, beside the single-child
  `StatelessSeed`/`StatefulSeed`/`Sprout`. Matched children (keyed by key,
  unkeyed by position) keep their branch identity across rebuilds; new children
  mount, removed children unmount, and child order follows `children`. The
  identical-config skip fast path and the duplicate-sibling-key debug guard are
  inherited from `Branch`. Additive; the spine is unchanged.

## 0.1.2

- Add a debug assertion that sibling keys are unique within `updateChildren`
  (debug-mode only; surfaces duplicate-key reconcile bugs earlier, no
  release-mode behavior change).

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev.
- Reworded the `TreeContext` use-after-unmount `StateError` message (text only; no behavior change).

## 0.1.0

- Initial release: the Seed/Branch keyed-reconcile engine — TreeContext (a separate capability handle), TreeOwner, the composition layer (Stateless/Stateful/State, InheritedSeed, Watch, Sprout), and the identical-config skip fast path.

  Pre-1.0 and experimental; APIs may change before 1.0.
