---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a36-dialogue-surface-root-type-is-immutable-across-apply-con
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A36"
---
## A36 (2026-06-14) — dialogue surface root type is immutable across apply; consumers must guard it  ·  AI

**Decision:** `DialogueSurface.apply` calls `root.update(newRootSeed)` unconditionally, and `Branch.update` asserts `Seed.canUpdate` (same runtimeType AND key). A consumer must enforce "the root component type is stable across re-emissions" itself (reject a root-type change before `apply`); the surface offers no guard, and for a render root a root-type change is unrecoverable (`mountRoot` asserts single root; `Stage` asserts sole `onNeedsFlush` owner — no teardown/remount path exists).
**Why:** a later `updateComponents` giving root id `root` a different type fails `canUpdate` (debug `AssertionError`; release: silent/corruption) and cannot remount.
**Affects:** `genesis_dialogue` (`DialogueSurface.apply` — candidate for a first-class root-type-stability precondition); `genesis_tree`/`genesis_typesetting` (single-root / single-Stage asserts); apps/console (root-type precondition). **Status:** pending.

