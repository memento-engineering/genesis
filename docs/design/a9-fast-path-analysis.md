# A9 fast-path analysis — the identical-config skip genesis_tree deliberately did not port

**Bead:** genesis-ak7 · **Author:** AI (analysis only — no implementation, no register write)
**Date:** 2026-06-12
**Provenance:** register A14 flagged: "Flutter's identical-config fast path (`identical(seed, newSeed) → skip`) was deliberately not ported; under A9 every in-place update cascades a subtree rebuild — the const-Seed/short-circuit pruning is the natural next optimization decision."
**Governs:** `packages/tree/lib/src/branch.dart` (`updateChild`/`updateChildren`/`update`/`rebuild`); reads against ADR-0001 Decisions 3–5, register A9/A11/A14.

---

## 1. What genesis does today

`Branch.updateChild` (branch.dart, lines 192–207) has no identity check — any non-null
`newSeed` that passes `canUpdate` runs `child.update(newSeed)` unconditionally:

```dart
Branch? updateChild(Branch? child, Seed? newSeed, Object? slot) {
  if (newSeed == null) {
    child?.unmount();
    return null;
  }
  if (child != null) {
    if (Seed.canUpdate(child._seed, newSeed)) {
      child.update(newSeed);
      return child;
    }
    child.unmount();
  }
  final branch = newSeed.createBranch();
  branch.mount(this, slot);
  return branch;
}
```

and `Branch.update` (A9 / ADR-0001 Decision 4) is unconditionally a force-rebuild:

```dart
void update(Seed newSeed) {
  ...
  _seed = newSeed;
  rebuild(force: true);
}
```

For a `ComponentBranch`, `performRebuild()` re-runs `build()` and reconciles the
child — which calls `updateChild` again — so **one in-place update at depth d
rebuilds the entire subtree below d**, even when every seed below is the same
object. `updateChildren` (lines 212–254) does **not** delegate to `updateChild`;
it has its own inline `canUpdate → match.update(newSeed)` path (line 235–237), so
any skip must land in both places (or `updateChildren` must be refactored to
delegate, Flutter-style — see §2).

Two concrete consequences in our architecture today:

1. **Provider updates are O(subtree), not O(dependents).** `InheritedBranch.update`
   notifies dependents, then `super.update` → `performRebuild` →
   `updateChild(_child, _typed.child, 0)`. Even when the surface author reuses the
   *same child instance* and only the provided value changed, the whole provided
   subtree force-rebuilds. `updateShouldNotify` currently gates *notification*,
   never *cost* — the dependent-targeting machinery (the whole point of the
   dependent set) is economically dead under the cascade.
2. **const-Seed pruning is impossible**, although our own test fixtures already
   write the pattern that would benefit: `_CountedSeed.build` returns
   `const Leaf('counted-child')` (a9_rebuild_on_update_test.dart) — Dart
   canonicalizes const instances, so every rebuild returns the *identical* object,
   and the fast path would prune there for free.

## 2. Flutter's exact behavior (the precedent)

Source: `/Users/nico/flutter/packages/flutter/lib/src/widgets/framework.dart`,
Flutter **3.44.0 stable** (`559ffa3f75e`).

### 2.1 `Element.updateChild` — the fast path (lines 3982, 4014–4022)

```dart
Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
  if (newWidget == null) {
    if (child != null) {
      deactivateChild(child);
    }
    return null;
  }

  final Element newChild;
  if (child != null) {
    var hasSameSuperclass = true;
    // When the type of a widget is changed between Stateful and Stateless via
    // hot reload, the element tree will end up in a partially invalid state.
    // ...
    assert(() {
      final int oldElementClass = Element._debugConcreteSubtype(child);
      final int newWidgetClass = Widget._debugConcreteSubtype(newWidget);
      hasSameSuperclass = oldElementClass == newWidgetClass;
      return true;
    }());
    if (hasSameSuperclass && child.widget == newWidget) {
      // We don't insert a timeline event here, because otherwise it's
      // confusing that widgets that "don't update" (because they didn't
      // change) get "charged" on the timeline.
      if (child.slot != newSlot) {
        updateSlotForChild(child, newSlot);
      }
      newChild = child;
    } else if (hasSameSuperclass && Widget.canUpdate(child.widget, newWidget)) {
      if (child.slot != newSlot) {
        updateSlotForChild(child, newSlot);
      }
      ...
      child.update(newWidget);
      ...
      newChild = child;
    } else {
      deactivateChild(child);
      ...
      newChild = inflateWidget(newWidget, newSlot);
    }
  } else {
    newChild = inflateWidget(newWidget, newSlot);
  }
  ...
  return newChild;
}
```

Three things to read precisely:

- **The skip condition is `child.widget == newWidget`** — *looks* like value
  equality, but `Widget` pins `operator==` to identity, `@nonVirtual` (lines
  364–371):

  ```dart
  @override
  @nonVirtual
  bool operator ==(Object other) => super == other;

  @override
  @nonVirtual
  int get hashCode => super.hashCode;
  ```

  `super ==` is `Object.==`, i.e. `identical()`. Flutter *forbids* subclasses
  from widening this — a value-equality `==` on a Widget would silently change
  reconcile semantics (equal-by-value configs would skip rebuilds) and put a
  potentially deep O(fields) comparison on the hottest path in the framework.
  Flutter's fast path is **identity-only by construction**.

- **Even on the skip, the slot is still updated** (`updateSlotForChild`) — an
  identical widget that *moved* must tell its render parent. (Genesis note:
  `Branch` stores no slot today — `mount` receives one and drops it; position
  lives only in the parent's child list — so there is nothing to update *yet*.
  This becomes an obligation the day render branches/typesetting grow slots.)

- **`hasSameSuperclass` is debug-only hot-reload armor** (the assert body) for
  Stateful↔Stateless swaps at the same tree location; in release it is
  constant `true`. It is orthogonal to the fast path and not needed for a
  first port.

### 2.2 `Widget.canUpdate` (line 382)

```dart
static bool canUpdate(Widget oldWidget, Widget newWidget) {
  return oldWidget.runtimeType == newWidget.runtimeType && oldWidget.key == newWidget.key;
}
```

Genesis's `Seed.canUpdate` is a verbatim port. Note `identical(a, b)` implies
`canUpdate(a, b)` trivially, so the skip strictly precedes — never conflicts
with — the existing branch arms.

### 2.3 Multichild and proxies

- Flutter's `Element.updateChildren` (line 4125) **delegates every pair to
  `updateChild`** (lines 4191/4255/4285: `final Element newChild = updateChild(...)`),
  so the fast path covers multichild automatically. Genesis's `updateChildren`
  is inline and would not be covered by patching `updateChild` alone.
- `ProxyElement.update` (line 6143) carries `assert(widget != newWidget);` —
  Flutter can *assert* an inherited element is never updated with an identical
  widget precisely because the fast path upstream guarantees it. The notify
  order (`updated(oldWidget)` → dependents' `didChangeDependencies()` →
  `markNeedsBuild()`, lines 5190–5194 — then `rebuild(force: true)`) is the
  order genesis already ported into `InheritedBranch.update` (A14: "notifies
  dependents BEFORE reconciling its child").

## 3. The correctness question: does provider invalidation survive the skip?

**Yes — verified by reading, this is the load-bearing check.** The worry: if a
provider's child subtree is skipped because the child seed is identical, do
dependents inside that subtree still rebuild?

The chain, from source:

1. `InheritedBranch.update` (inherited.dart, lines 90–108) notifies dependents
   **before** `super.update` reconciles the child: `dep.dependencyChanged()`.
2. `Branch.dependencyChanged` → `markNeedsRebuild()` (branch.dart, lines 71–81):
   sets `_dirty` and calls `owner?.scheduleRebuildFor(this)` —
   **independent of the update cascade**; it goes through the owner's dirty set.
3. `TreeOwner.flush` (tree_owner.dart, lines 70–95) drains depth-ordered and —
   documented and implemented — "**Branches dirtied mid-flush are rebuilt in
   the same pass and included**" (the `while (_dirtyBranches.isNotEmpty)` loop
   re-reads the set every iteration).
4. `StatefulBranch.dependencyChanged` additionally sets
   `_needsDidChangeDependencies`, consumed by its next `performRebuild` —
   whichever path triggers it (stateful.dart, lines 84–101).

So with the skip in place: provider value changes, dependents are marked dirty
and scheduled, the (identical) child subtree is *not* cascaded, and each
dependent rebuilds **exactly once** when the owner drains it — same pass if the
provider update happened mid-flush, next flush (after `onNeedsFlush` fired on
the empty→non-empty edge) if it happened outside one. Dependents are always
strictly deeper than their provider, so depth-ordered drain cannot have already
built them when notification lands — the `scheduleRebuildFor` re-dirty assert
cannot trip.

**Two observable deltas, to record honestly:**

- **A14 flush inclusion-rule delta.** Today a dependent is force-rebuilt by the
  cascade (dirty flag cleared early), so the drain *excludes* it from
  `flush()`'s returned list. With the skip, the dependent is rebuilt *by the
  drain* and **included**. For render backends this is strictly better
  reporting (spike 4's dirty-region mapping wants exactly "what rebuilt"), but
  it is a contract change A14's wording must absorb.
- **Timing delta outside a flush.** Today `root.update(...)` synchronously
  rebuilds dependents via the cascade; with the skip (and an identical provider
  child) they rebuild at the next `flush()`. Embedders already must flush on
  `onNeedsFlush` (setState has the same shape), and the wire path never
  produces identical seeds (§4.3), so this only affects in-process surfaces
  that opt into instance reuse — but it needs a test pinning the semantics.

## 4. Where updates actually come from, surface by surface

### 4.1 Measurement (perception) — re-harvests often, but dirties at the leaves

Perception's invalidation enters via `setState`/`markNeedsHarvest` at the
dirtied element and via provider invalidation — `markNeedsRebuild()` funnels
into `markNeedsHarvest` (A15), which super-calls the tree path. Flush-driven
rebuilds start *at* the dirty branch, so the fast path buys nothing for
leaf-dirty re-harvest. It pays inside perception when a *container's* builder
re-runs and re-emits const/cached children (`Node` children are `List<Seed>`;
`Field` is a const-friendly leaf): unchanged sub-measurements prune instead of
re-running. Harvest output is unaffected either way — harvest walks the
mounted tree, and a skipped branch still holds the same seed.

### 4.2 Expression surfaces, in-process — the real win

This is Flutter's own economics, and ours: a `setState`/update near the root
re-rebuilds everything below it today. With the skip, `const` seeds (Dart
canonicalization makes every `const Leaf('x')` at the same call site identical)
and cached child instances (`InheritedSeed(value: v, child: prebuiltChild)`)
prune entire subtrees. Provider updates drop from O(subtree) to
O(dependents) + the reconcile spine above the skip point. The A4/typesetting
dirty-region economics (spike 4: 268 bytes vs 10530 across ten updates,
"the static element never rebuilt") only hold when updates enter from above
*if* static subtrees can actually short-circuit — without the fast path, a
top-down update storm rebuilds every static box and the backend repaints
everything.

### 4.3 The wire path (A2UI re-emission) — the fast path does NOT help, honestly

`genesis_dialogue` deserializes `updateComponents` payloads into fresh `Seed`
instances every time. **Deserialized seeds are never `identical()`**, so under
option (a) a whole-tree re-emission still cascades exactly as today. This is
not a flaw to paper over; it is a layering fact: wire-cost containment belongs
*in the dialogue package* — diff incoming component maps against the previous
emission by key and only `update()` the components whose payload changed —
which is also what A2UI's flat-keyed grammar is *for* (A3: "whole-(sub)tree
emission reconciles to a patch by key"). Pushing wire economics into `Seed`
equality (option b) solves the wrong layer with the sharpest tool.

## 5. Options

### Option (a) — port the fast path: `identical(child.seed, newSeed)` → skip

In `updateChild`, before the `canUpdate` arm:

```dart
if (child != null) {
  if (identical(child.seed, newSeed)) {
    return child;
  }
  if (Seed.canUpdate(child._seed, newSeed)) { ... }
}
```

and the same guard in `updateChildren`'s match arm (or refactor
`updateChildren` to delegate pairs to `updateChild`, mirroring Flutter — the
cleaner shape, and it keeps a single skip site). `Branch.update` itself stays
force-semantics (Flutter's `Element.update` also has no identity check — the
skip is reconciliation's concern; direct `update()` callers keep A9 exactly).

A deliberate genesis refinement over Flutter: use **`identical()` explicitly**,
not `==`. Flutter writes `child.widget == newWidget` and then pins `Widget.==`
to identity with `@nonVirtual` to keep that expression honest. Genesis should
*not* pin `Seed.operator==` — the house freezed plans (ADR-0001 Decision 7)
want value equality on data seeds for wire diffing and testing — and instead
make reconciliation immune to whatever `==` seeds define. Same semantics as
Flutter, fewer constraints on the config type.

- **Buys:** const-Seed subtree pruning; provider updates at O(dependents);
  preserves the A4 dirty-region economics under top-down updates; restores the
  `ProxyElement`-style invariant (update never sees an identical config).
- **Costs:** the A14 flush inclusion-rule delta and out-of-flush timing delta
  (§3) must be tested and re-worded; the skip must cover both reconcile sites;
  a slot-update obligation lands the day branches grow slots (§2.1); seeds
  that are *mutated* in place (illegal but unenforced — `Seed` fields are
  final by convention) would now silently skip their rebuild.

### Option (b) — `==`-based skip (value equality on Seeds)

`if (child.seed == newSeed) return child;` with freezed-style `operator==` on
seed classes. The only option that would *also* help the wire path (two
deserializations of the same component compare equal).

- **Buys:** wire-path pruning without a dialogue-layer diff.
- **Costs:** Flutter explicitly forbids this shape (`@nonVirtual ==`, §2.2) —
  for reasons that bind harder on us: (i) deep value comparison on the hottest
  reconcile path, O(fields·depth) per frame, can cost what the skipped rebuild
  cost; (ii) builder-carrying seeds (`Watch.builder`, any closure field) never
  compare equal — closures have identity equality — so the skip silently
  stratifies into "works for data seeds, never for composition seeds";
  (iii) rebuild-or-not starts depending on how thoroughly a domain author
  wrote `==` — a correctness knob disguised as an optimization. The wire
  problem it solves is better solved at the dialogue layer by key/payload
  diffing (§4.3). **Not now; revisit only with freezed evidence in hand, as a
  separate register entry.**

### Option (c) — keep the cascade (status quo) with measured cost

Defensible while both consumers are small: trees are tens of nodes, flushes
are synchronous, no one has measured a hot path yet. But three facts argue it
has already expired: provider updates being O(subtree) makes the dependent-set
machinery cost-free in name only; the codebase's own fixtures already write
const-canonicalized children the engine then pointlessly rebuilds; and the
typesetting backend (next consumer) is *premised* on locality the cascade
destroys for top-down updates. Keeping (c) means re-litigating this at
typesetting time with more consumers locked to cascade timing.

### Micro-benchmark sketch (do not build yet)

Chain of N=1000 nested `StatelessSeed`s whose builders return a cached child
below depth k; one `update()` at the root; count builder invocations and wall
time with/without the skip, k ∈ {1, 500, 999}. Second scenario: one
`InheritedSeed` over a 1000-leaf `Node` with d ∈ {1, 100} dependents; measure
builds per value change. Expected: builds drop from O(N) to O(k) and from
O(N) to O(d) respectively; wall-time ratio is the publishable number. Belongs
next to the spike-4 economics evidence in `docs/evidence/` if ever built.

## 6. Recommendation

**Port the fast path (option a), as `identical()` — not `==` — in both
`updateChild` and `updateChildren` (preferably by refactoring `updateChildren`
to delegate to `updateChild`, Flutter's shape), leaving `Branch.update` force
semantics untouched and `Seed.operator==` unpinned for future freezed use.**
Confidence: high — Flutter has shipped exactly this skip for a decade; the one
genesis-specific hazard (provider invalidation under a skipped subtree) is
disproven by reading `inherited.dart` + `tree_owner.dart` (§3) and is pinned
by the proposed tests. Record honestly: the wire path gains nothing (§4.3);
its economics belong to `genesis_dialogue`.

### Tests that would gate the change

1. **Skip-on-identical:** `updateChild` with an identical seed returns the same
   branch and the child's `performRebuild` does not run (builder counter == 0).
2. **const pruning:** parent whose `build()` returns a const child — parent
   `update()` re-runs the parent builder once; child and grandchild builders do
   not re-run; branch identity preserved (`same()`).
3. **Identity-only, not value:** a test seed overriding `operator==`/`hashCode`
   to value equality still rebuilds when a non-identical equal seed arrives —
   pins `identical()` semantics against freezed drift.
4. **Provider invalidation survives the skip:** `InheritedSeed` whose new config
   reuses the *identical child instance* with a changed value — each dependent
   rebuilds exactly once, `didChangeDependencies` fires before its build,
   non-dependent siblings in the skipped subtree never rebuild.
5. **A14 inclusion delta pinned:** in scenario 4, `flush()`'s returned list
   includes the dependents (drain-rebuilt), still excludes cascade
   force-rebuilds; `onNeedsFlush` fired on the empty→non-empty edge.
6. **Out-of-flush timing pinned:** provider update outside a flush with an
   identical child — dependents are dirty (not yet rebuilt) until `flush()`,
   then rebuild exactly once.
7. **Multichild coverage:** `updateChildren` with a keyed child moved to a new
   position under an identical seed — no rebuild, identity preserved, new order
   reflected in the parent's children.
8. **Direct `update()` unchanged:** calling `branch.update(sameSeedInstance)`
   directly still force-rebuilds (A9 core semantics; the skip lives in
   reconciliation only).
9. **Wire realism guard (documentation-as-test):** two structurally equal but
   distinct seed instances (simulating double deserialization) do NOT skip.
10. **Perception conformance:** existing perception suite green; a harvest
    over a tree containing a skipped subtree yields a byte-identical
    Observation.

## 7. Proposed register entry (for the keeper — not written to ADR-0000 by this analysis)

See the orchestrator payload (`proposedRegisterEntry`); summary: A18, port the
identical-config fast path as `identical()`-based skip in both reconcile sites,
`Seed.==` left free, A14 inclusion-rule delta recorded, wire path explicitly
out of scope (dialogue-layer diffing instead). Status: pending.
