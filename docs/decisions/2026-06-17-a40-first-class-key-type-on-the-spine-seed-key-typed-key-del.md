---
status: accepted
date: 2026-06-17
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a40-first-class-key-type-on-the-spine-seed-key-typed-key-del
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A40"
---
## A40 (2026-06-17) — First-class `Key` type on the spine; `Seed.key` typed `Key?`; deliberately no `GlobalKey`  ·  AI

**Decision:** `tree` gains a first-class, `@immutable` `Key` value-type (`packages/tree/lib/src/key.dart`) with two concrete kinds — `ValueKey<T>(value)` (value `==`/`hashCode`, type parameter part of identity) and `ObjectKey(value)` (identity `==`) — plus an ergonomic `const factory Key(String) = ValueKey<String>`. `Seed.key` is **retyped from `Object?` to `Key?`** (and `Branch.key`, `TreeContext.key`, `SproutContext.key`, `PerceptionContext.key` follow); `Branch.updateChildren`'s keyed map is now `Map<Key, Branch>`. This was the bead's *primary* request ("used as `Seed.key`'s type") over the offered weaker alternative ("accepted alongside `Object?`"), chosen because only the typed form closes the stated gap — a bare `Object` key has no intent and admits accidental cross-type collisions (`1` the int vs `1` the num). `Key` is left **open** (abstract, not sealed) so domains define their own kinds; `typesetting`'s render-scope wrapper key now `extends Key` (was a bare class). **No `GlobalKey`** (cross-tree lookup is refused — cross-boundary references pass handles through the parent, keeping the tree one-way; a future global-lookup need must be a separate, explicit, opt-in mechanism) and **no `LocalKey` layer** (vacuous once there is no global key; the concrete kinds extend `Key` directly). The A2UI "tree key == component id" bridge (ADR-0003) is preserved *representationally*: `buildSeedTree` wraps each wire id in `ValueKey<String>(id)` at the one seam, and `ConsentRouter`'s id→branch hit-test compares against `ValueKey(id)`.
**Why:** as `the_grid` adopts `genesis_tree` for desired-state authoring (M4 config substrate) and multi-child keyed list-reconcile lands (`genesis-7r9`), keyed identity becomes load-bearing: it needs (1) type-safety/intent on the key and (2) a shared identity story for keyed reconcile. Faithful to Flutter's `Key`/`ValueKey`/`ObjectKey` (the engine's origin) minus the `GlobalKey` "original sin". Pre-1.0/experimental, so the breaking type change is sanctioned (CHANGELOG `genesis_tree` 0.1.3); the whole pub workspace was migrated green (analyze + test + format).
**Affects:** **breaking** — `genesis_tree` public API (`Seed`/`Branch`/`TreeContext`); every workspace package that keyed a seed with a raw `String`/`Object` migrates to `ValueKey` (`perception`, `typesetting`, `taxonomy` `SeedFactoryFn`/`buildComponent` key param, `consent` router, all tests/fixtures); downstream consumers (`com.nicospencer/lenny`, `engineering.memento/the_grid`) inherit the typed key when they bump the ref. Pairs with `genesis-7r9` (multi-child keyed reconcile) and reinforces A33/A38 (one-branch-per-key; the render-scope wrapper is now a typed `Key` distinct from the child's). Unit tests: `packages/tree/test/key_test.dart`. **Status:** promoted to ADR-0001 Decision 2.

