---
status: accepted
date: 2026-09-03
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: release-mode-tree-invariants-throw-in-release
  surfaces:
    - "packages/tree/**"
    - "packages/dialogue/**"
  obsoletes: []
  updates:
    - a36-dialogue-surface-root-type-is-immutable-across-apply-con
    - a38-domain-authoring-rule-a-component-s-build-must-not-key-a
  obsoleted-by: null
  updated-by: []
  bead: genesis-7ob
---
## (2026-09-03) — The three tree corruption guards throw in release, not only under assertions · decider: Nico

**Decision:** the re-dirty guard (`TreeOwner.scheduleRebuildFor`), the duplicate-sibling-key guard (`Branch.updateChildren`), and the `canUpdate` guard (`Branch.update`) are plain checks that throw `StateError` in every build mode, with the semantics their assertions had. `DialogueSurface.apply` additionally verifies root compatibility itself before calling `root.update`, and commits `surfaceId` only after the update returns. No degrade-and-flare, no recovery path, no new pass bound: one build per branch per flush pass is the bound, and a violation is a programming error that must fail loudly.

**Why:** each guard protected against silent corruption, and each was tree-shaken out of release. The re-dirty guard's absence let a release drain loop forever; the key guard's absence let a shadowed sibling be unmounted during reconcile; the `canUpdate` guard's absence let an incompatible config be swapped into a mounted branch, with `DialogueSurface` committing its metadata before the update that would fail.

**Updates:** `a38-domain-authoring-rule-a-component-s-build-must-not-key-a`, whose substrate-hardening clause records the duplicate-key guard as "Debug-only (tree-shaken in release)" — it is now unconditional and O(n) in the child count. `a36-dialogue-surface-root-type-is-immutable-across-apply-con`, which states "the surface offers no guard" and puts root-type stability on the consumer — the surface now guards it. The A36 invariant itself is unchanged: a root-type change is still unrecoverable and still rejected; the surface names it instead of corrupting.

**Affects:** `genesis_tree` 0.3.1, `genesis_dialogue` 0.1.2 (patch releases, no API change); `genesis_perception` tests, which inherit the spine's behaviour. **Status:** accepted.
