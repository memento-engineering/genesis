# Changelog

## 0.4.0-dev.1

Prerelease on the `dev` rung: this wave is additive over 0.3.1 (nothing published in 0.3.1 is removed or changed) and its API is still moving; stable `0.4.0` is a separate, human-promoted act.

- Add the provider composition family to the tree composition layer: the dependency-free provider primitives (`Provider`, `ProviderScope`, `ProviderTreeContext`, `AvailabilityRegistry`, `LifecycleProvider`) and their contract suite, lifted out of `grid_engine`'s private sources and exported publicly. The provider kind-swap check is an independent `StateError` in every build mode.
- Add the lifecycle phase guard (`TreeLifecyclePhase`, `TreeLifecyclePhaseGuard`, `TreeOwner.lifecyclePhaseGuard`): one lifecycle phase definition for tree drivers, composed with the owner flush marker; retained-context dependency registration before mutation is rejected.
- Add the proxy provider ladder (`ProxyProvider` through `ProxyProvider6`): one- through six-input proxy providers that derive owned ambient values through the existing provider lifecycle and availability registry, sharing replacement and teardown ownership across providers.
- Add lifecycle participation for long-lived non-node values (`TreeLifecycleParticipant`, `TreeSnapshotReader`, `TreeWatchingReader`): call-scoped snapshot and watching readers driven through the shared phase guard, with mounted identity retained across reconciliation; only participants the provider constructed are disposed. Retained reader use and invalid in-place participant replacement fail loudly in every build mode.
- Add dependency supersession scopes (`TreeDependencyScope`): `TreeLifecycleParticipant.didChangeDependencies` receives a retainable scope that becomes non-current on the next pass or on teardown, and the provider invalidates scopes before participant disposal for owned and adopted participants alike, so continuation staleness stays out of the synchronous build path.
- Fix: mid-flush dirties are guarded by build ancestry, so a cascade-dirtied descendant no longer trips the one-build-per-branch invariant.

## 0.3.1

- Three tree invariants were debug-only assertions and vanished from release builds; **release builds now enforce** all three, throwing `StateError` with the message the assertion carried. (1) `TreeOwner.flush` rejects a branch re-dirtied after it was already built in the pass — a branch that calls `setState` from inside its own `build` used to drain forever in release; the pass is bounded at one build per branch. (2) `Branch.updateChildren` rejects duplicate non-null sibling keys before it touches the old child list, so a rejected reconcile leaves the mounted tree unchanged. (3) `Branch.update` rejects a seed that fails `canUpdate` instead of swapping in an incompatible config. No API change; code that relied on catching `AssertionError` from these three paths now catches `StateError`.

## 0.3.0

- **Breaking:** aspect-scoped inherited dependencies. `InheritedBranch.addDependent` is now `addDependent(Branch branch, {Object? aspect})`, and `dependOnInheritedSeedOfExactType<T>()` gained an optional `{Object? aspect}` on `Branch`, `TreeContext`, and `SproutContext`. Migration for a subclass that overrides `addDependent`: add the named parameter and forward it — `void addDependent(Branch branch, {Object? aspect}) => super.addDependent(branch, aspect: aspect);` — which preserves the base provider's rejection of an aspect it has no vocabulary for. An external `TreeContext` implementation adds `{Object? aspect}` to its `dependOnInheritedSeedOfExactType` and passes it straight through to the handle it wraps. Call sites that pass no aspect are unchanged.
- Add `InheritedModelSeed<T, A>` and `InheritedModelBranch<T, A>`: an ambient value whose dependents may subscribe to a single ASPECT of it. A dependent that passes `aspect:` is invalidated only when `updateShouldNotifyDependent` reports the change as touching one of the aspects it asked for; omitting the aspect keeps the whole-value dependency `InheritedSeed` always gave. Lookup is unchanged — still the nearest provider of exact value-type `T` — so a plain `InheritedSeed<T>` provider throws `ArgumentError` for a non-null aspect, and a model provider throws for an aspect of the wrong type. Experimental, like the rest of the composition layer.

## 0.2.0

- **Breaking:** `debugFillProperties` now receives a `DiagnosticsBuilder` — replace `properties.add(...)` list calls with the builder `add()`; wire format unchanged.

## 0.1.6

- Add `genesis_foundation ^0.1.1` below the tree spine and re-export its
  dependency-free diagnostics protocol and typed snapshot contract. The
  first-class `Key` types remain owned by `genesis_tree`.

## 0.1.5

- Docs only, no API changes. The README gains **"The artifact layer —
  deliberately not shipped"**: `genesis_tree` reconciles desired state into
  live identity and stops there — what that identity spawns and owns is the
  consumer's, unbundled into four pieces (artifacts / owner / protocol /
  affordance scopes), with `genesis_typesetting` and `genesis_perception` as
  the worked examples. The composition-layer list also catches up to 0.1.4
  (`MultiChildSeed`, the `SingleChildSeed`/`Nest` chain).

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
