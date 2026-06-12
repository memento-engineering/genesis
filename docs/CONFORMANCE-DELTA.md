# Conformance delta ledger — perception rebuild (A10 campaign)

lenny's perception test suite (`com.nicospencer/lenny/packages/perception/test/`)
is the conformance gate for the perception rebuild on the tree spine
(ADR-0001 Decision 8: one campaign, perception's existing suite as the gate,
modulo the deliberate Decision 4 delta). Every original test has a counterpart
in `packages/perception/test/`; original file names are kept
(`element_lifecycle_test.dart`, `perception_owner_test.dart`,
`stateless_perception_test.dart`, `stateful_perception_test.dart`,
`inherited_perception_test.dart`, `node_test.dart`, `watch_test.dart`,
`no_flutter_test.dart`), plus new coverage for `Field` (`field_test.dart`) and
the `PerceptionContext` capability handle (`perception_context_test.dart`).

This ledger records every test whose **expectation was amended**, with the
register/ADR entry justifying it, followed by the vocabulary/structural
mappings that change no behavior.

---

## Amended expectations

### 1. `stateless_perception_test.dart` — `'no rebuild when provider value unchanged'` → `'no dependent invalidation when provider value unchanged'`

- **Original expectation (lenny):** after `ipEl.update(...)` with an equal
  provider value (`updateShouldNotify == false`) and a flush,
  `tracker.builds == 1` — the child's builder did not re-run, because
  `update()` swapped config without invoking builders.
- **New expectation (genesis):** `tracker.builds == 2`, and — strengthened —
  `owner.flushHarvest()` returns empty, proving `updateShouldNotify=false`
  scheduled **no dependent invalidation**. The extra build is the update
  cascade re-running the child's `build()` because the child received a new
  config instance; it is not a dependent notification.
- **Justification:** register **A9** → **ADR-0001 Decision 4** (config update
  invokes the rebuild hook). The test's true subject — no invalidation when
  the provided value is unchanged — is preserved and now asserted directly.

### 2. `stateless_perception_test.dart` — `'child remounted when canUpdate=false (key change)'`

- **Assertions unchanged** (old child unmounted, new child mounted, identity
  swapped).
- **Semantics note:** under **A9 / ADR-0001 Decision 4**, `el.update(...)`
  alone now re-runs `build()` and swaps the child; the original suite's
  explicit `markNeedsRebuild()` + `flushHarvest()` is retained verbatim but is
  redundant. Recorded so nobody reads the explicit dirty/flush pair as
  load-bearing.

### 3. `stateful_perception_test.dart` — `'state.context is the element (implements PerceptionContext)'` → `'state.context is the capability handle bound to the element (A8)'`

- **Original expectation (lenny):** `state.context.perceptionId ==
  el.perceptionId`, where `state.context` **was** the element —
  `PerceptionElement implements PerceptionContext` (lenny ADR 0001's
  re-commitment of Flutter's Element≡BuildContext sin).
- **New expectation (genesis):** `state.context` is a `PerceptionContext`
  whose `perceptionId` equals the element's `branchId`, **and** is not
  `same(element)` and not a `Branch` at all — the handle is a separate,
  invalidatable object.
- **Justification:** register **A8** → **ADR-0001 Decision 2**
  (separate-handle fork) and **A12** (`PerceptionContext` is a capability
  extension of `TreeContext`, layered onto the handle).

### 4. `inherited_perception_test.dart` — `'InheritedPerceptionElement is a PerceptionElement'` → `'InheritedPerceptionElement is a tree Branch (A12 layering)'`

- **Original expectation (lenny):** the inherited element
  `isA<PerceptionElement>` — everything descended from the single domain
  element base.
- **New expectation (genesis):** `isA<InheritedBranch<String>>` and
  `isA<Branch>`. Composition elements are tree types; only artifact elements
  (`NodeElement`, `FieldElement`, custom measurement leaves) extend
  `PerceptionElement`.
- **Justification:** register **A11/A12** → **ADR-0001 Decisions 3 and 6**
  (composition is tree-owned; perception subclasses the spine rather than
  re-deriving the composition layer).

### 5. `watch_test.dart` — `'createElement returns StatefulElement with WatchState'` → `'createBranch returns StatefulBranch with WatchState'`

- **Original expectation (lenny):** `Watch.createElement()` is a perception
  `StatefulElement`.
- **New expectation (genesis):** `Watch.createBranch()` is tree's
  `StatefulBranch` (state still `isA<WatchState<int>>`); all behavioral
  assertions (initial value, emits, cancel-on-dispose) unchanged.
- **Justification:** register **A13** (Watch lives in tree's composition
  layer; perception consumes it via re-export, not subclassing).

---

## Vocabulary / structural mappings (no behavior change)

| lenny perception | genesis perception | Where decided |
|---|---|---|
| `PerceptionOwner.flushHarvest()` (void) | `PerceptionOwner.flushHarvest()` → `List<Branch>`, alias of `TreeOwner.flush` | A12 + ADR-0001 Decision 5 (drained set exposed) |
| `PerceptionOwner.onNeedsHarvest` | retained — alias of `TreeOwner.onNeedsFlush` | A12 |
| `PerceptionElement.markNeedsHarvest()` | retained — delegates to `Branch.markNeedsRebuild`; tree invalidation funnels back through it, so overriding it still observes provider invalidation (kept lenny's `_E.markNeedsHarvest` override tests valid) | A12 |
| `perceptionId` | retained on `PerceptionElement` and `PerceptionContext` as alias of `branchId`; composition elements (tree types) expose `branchId` only — ports of id-identity assertions over mixed children use `branchId` | A12 |
| `Perception.createElement()` | retained as the domain factory; `createBranch()` bridges to it | A12 |
| `PerceptionContext.dependOnInheritedPerceptionOfExactType<T>()` | **not aliased** — ports call `dependOnInheritedSeedOfExactType<T>()` (matching is by value type, so the provider-named alias was misleading) | A12 consequence: tree types surface |
| `PerceptionState.perceived(fn)` | retained — alias of `State.setState` | tree register (setState-analogue) + A12 |
| `PerceptionState.perception` | retained — alias of `State.seed` | tree register (`state.seed`) + A12 |
| `InheritedPerceptionElement.childElement` | `childBranch` (inherited from `InheritedBranch`) | tree register rename |
| `StatelessElement` / `StatefulElement` | `StatelessPerceptionElement` / `StatefulPerceptionElement` — thin subclasses of tree's `StatelessBranch`/`StatefulBranch` that upgrade the handle to `PerceptionContext` | A12 |
| `Node.children: List<Perception>` / `NodeElement.children: List<PerceptionElement>` | `List<Seed>` / `List<Branch>` — Nodes mix artifact and composition children | A12 (tree types surface) |
| `perception_owner_test.dart` `'end-to-end'` | assertion unchanged (`lastValue == 7`); under A9 the dependent reads the new value during the update cascade rather than at drain time | A9 / ADR-0001 Decision 4 |
| `node_test.dart` update tests | assertions unchanged; `NodeElement` reconciles children in `performRebuild` (reached automatically by `update()` under A9) instead of an explicit `update()` override | A9 / ADR-0001 Decision 4 |
