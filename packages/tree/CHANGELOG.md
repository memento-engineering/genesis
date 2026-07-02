# Changelog

## 0.1.4

- Add the single-child *chain* vocabulary. `SingleChildStatelessSeed` and
  `SingleChildStatefulSeed` (with `SingleChildState`) are the single-child
  analogues of `StatelessSeed`/`StatefulSeed`: their build receives the
  downstream child to embed (`buildWithChild`). `Nest` stacks a list of them
  into a vertical spine, each wrapping the next down to one leaf `child` — the
  `Nested`/`MultiProvider` shape, generic (no inherited-value semantics baked
  in). `MultiChildSeed` fans out horizontally; `Nest` composes vertically.
  Fully `const`-constructible: the children are referenced as authored and never
  reconstructed — each link's downstream is supplied at the branch layer — so an
  unchanged `Nest` prunes its whole chain on reconcile, while a change to the
  leaf or any link propagates through it. EXPERIMENTAL.

- Add `getInheritedSeedOfExactType<T>()` — the dependency-free counterpart of
  `dependOnInheritedSeedOfExactType<T>()`. Same nearest-ancestor lookup, same
  value result, but the caller is **not** registered as a dependent: the
  returned value is a snapshot, and a later change to the provided value does
  not rebuild the reader. Use it for one-shot reads — grabbing an ambient
  service in `State.initState`, inside an effect, during teardown — and keep
  the depend variant wherever the branch must rebuild on change. Available on
  `Branch`, `TreeContext`, and `SproutContext`. **Breaking for external
  `TreeContext` implementers** (a new interface member); handles that wrap
  the canonical handle just delegate it.
- `StatefulBranch` now asserts (debug-only) when
  `dependOnInheritedSeedOfExactType` is called during `initState` or
  `dispose`. In `initState` the natural cache-the-result pattern goes stale
  when the provider changes (initState never re-runs) — read dependency-free
  with the new variant, or cache-and-track in `didChangeDependencies`. In
  `dispose` the branch is unmounting and can never observe a change.
- There is deliberately no "get the provider element" lookup (Flutter's
  `getElementForInheritedWidgetOfExactType`): the capability handle never
  exposes a `Branch`.

## 0.1.3

- **Breaking:** a first-class `Key` value-type. `Seed.key` (and `Branch.key`,
  `TreeContext.key`) is now typed `Key?` instead of `Object?`. Two concrete
  kinds ship: `ValueKey<T>(value)` (value equality; the type parameter is part
  of identity, so `ValueKey<int>(1) != ValueKey<num>(1)`) and `ObjectKey(value)`
  (identity equality), plus an ergonomic `const Key(String)` factory that builds
  a `ValueKey<String>`. The typed key gives reconciliation identity intent and
  type-safety and a shared identity story for keyed list reconcile.
- `Key` is **open** (abstract, not sealed): domains extend it with their own key
  kinds. There is deliberately **no `GlobalKey`** — cross-tree lookup is refused
  so the tree stays one-way (cross-boundary references pass handles through the
  parent) — and no `LocalKey` layer (vacuous without a global key).
- Migration: replace `key: 'id'` with `key: ValueKey('id')` (or `Key('id')`),
  and `seed.key == 'id'` comparisons with `seed.key == ValueKey('id')`.
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
