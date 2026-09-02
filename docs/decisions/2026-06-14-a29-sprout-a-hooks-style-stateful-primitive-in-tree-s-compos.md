---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a29-sprout-a-hooks-style-stateful-primitive-in-tree-s-compos
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A29"
---
## A29 (2026-06-14) — `Sprout`: a hooks-style stateful primitive in `tree`'s composition layer  ·  AI

**Context (Nico, 2026-06-14):** heading toward a public 1.0, cut the Flutter-style `Stateful`/`State` boilerplate — *the last feature before feature-freeze*. The load-bearing constraint (architecture review): the `Seed` subclass's `runtimeType` IS the reconciliation tag (`Seed.canUpdate` keys on it), so it can't be replaced by a `createBranch` factory field (collapses all seeds to one type) or by the Branch type (shared: every stateless seed → `StatelessBranch`, every stateful → `StatefulBranch`). The fix is therefore not removing subclassing but removing the *separate `State` class*; hooks put state on the persistent branch, declared inline in `build`.

**Decision (as built, additive; tree 120→142, perception 104 unchanged — the spine is untouched, the conformance gate holds; analyze + format clean; two tamper probes each tripped a distinct test):**
- **`Sprout extends Seed`** with `@protected Seed build(SproutContext)`; `SproutBranch extends ComponentBranch` (reuses `_child`/`updateChild`/`visitChildren`/first-build-on-mount); `SproutContext implements TreeContext` wrapping the canonical A8 handle (the `PerceptionContext` idiom → throw-after-unmount inherited). The `Sprout` subclass stays the reconcile tag; state lives on the branch in call-order-indexed slots; the handle is the only object `build` receives.
- **v1 hooks:** `useState<T>(initial) → StateCell<T>` (`.value` get/set; setter always marks rebuild, matching `State.setState`; persists across config update, ignoring the new initial — the A9 rule; plus a functional `set`); `useStream<T>(stream, {initial}) → T` (subscribe, cancel on unmount); `useEffect(Dispose? Function(), [keys])` (microtask-deferred passive effects; `[]`=once, `null`=every build, non-empty=on key change; cleanup before re-run and on unmount); `useMemo<T>(create, keys)`.
- **Effect timing = microtask-passive** (`scheduleMicrotask` in `_scheduleEffects`, after `super.performRebuild`): an effect's `markNeedsRebuild` lands in a *fresh* flush pass, so it provably cannot trip `TreeOwner`'s `_builtThisPass` re-dirty assert. A synchronous `useLayoutEffect` is deferred.
- **Rules of hooks:** slot type-drift and BOTH count-drift directions (over- and under-count) → **always-on throw** (either would silently misbind slots); call-outside-`build` and set-state-during-`build` → **debug assert**. A same-shape reorder (same count + types) is undetectable — the positional-hooks caveat, documented. Disposal runs slot teardowns in **reverse order** (cancel streams, run effect cleanups), each **guarded** so one throwing user cleanup can't strand a sibling teardown or break the tree unmount (the first error rethrows after all teardowns + `super.unmount`).
- **Effect re-runs are two-phase** (React order): all previous cleanups, then all effects, so a cleanup that frees a resource runs before any effect re-acquires it.
- **`Watch` kept** (additive; perception re-exports it). **`PerceptionSprout` deferred** — `Sprout` has zero consumers yet (the two-consumer rule applies to it first; perception gets it free via re-export).
- **Adversarial pass (skeptic, 25 tests + 2 tamper probes):** fixed a HIGH (a throwing effect cleanup stranding a sibling stream cancel + corrupting unmount → now guarded), promoted under-count from debug-assert to always-on throw, switched effects to two-phase ordering, and added the set-during-build debug guard. The `StateCell` setter is a deliberate no-op after unmount (mirrors `setState`), *not* the A8 handle's throw — documented.

**Two deviations from the approved plan, surfaced during the build (flag):**
1. **The `useState` cell is `StateCell<T>`, not `Cell<T>`** — `Cell` collided with `genesis_typesetting`'s grid `Cell` (typesetting consumes the spine), an `ambiguous_import` error. `StateCell` is collision-free and self-documenting; lesson: generic public names on the core spine clash with consumers.
2. **`useStream` compares sources by `==`, not `identical`** — `StreamController.stream` returns a new wrapper each access but compares `==` for the same controller, so `identical` would needlessly re-subscribe every build. `==` treats "the same stream" as unchanged; derived streams (map/where) compare unequal and should be stabilized via `useMemo`.

**Flagged for Nico (defaults applied; flip any):** name `Sprout` (not `Seedline`) · `StateCell<T>` · microtask-passive effects (no `useLayoutEffect`) · always-dirty `useState` setter · `useStream` `==` semantics + keep-last-value on swap · `useReducer`/`PerceptionSprout` deferred · the composition layer stays EXPERIMENTAL (two-consumer rule — `Sprout` itself has only its tests as a consumer so far).
**Affects:** ADR-0001 D3 (composition layer) at next promotion; perception/expression/agent-loop consumers that may adopt `Sprout`; overlaps A28 flag 1 (a `Sprout` `useAction` hook could later subsume the action-dispatch seam). **Status:** promoted → ADR-0001 D3, 2026-06-14 (all flagged defaults ratified as-built).

