---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a14-tree-api-surface-decisions-from-the-extraction-build-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A14"
---
## A14 (2026-06-11) — `tree` API surface decisions from the extraction build  ·  AI

**Decision (as built, commit `d035c60`; adversarially verified incl. tamper probe):**
- **`TreeOwner.flush()` → `List<Branch>`** — drains depth-ordered, returns the branches *this call* rebuilt; inclusion rule: drained ∧ mounted ∧ still-dirty at drain time (A9-cascade force-rebuilds and unmounted stragglers excluded). `onNeedsFlush` fires on the empty→non-empty edge. *(A18 delta, landed `4daada8`: a dependent under an identical-skipped subtree is no longer force-rebuilt by a cascade, so it stays dirty, drains, and is now **included** in the returned list — pinned by `a18_fast_path_test.dart` #5. The cascade-force-rebuild exclusion still holds for the non-identical path.)*
- **`State.setState(fn)`** keeps the Flutter name (perception aliases `perceived()`); State's config getter is **`seed`**.
- **`visitChildren(visitor)`** — shallow, direct children, tree order; base visits nothing; callers recurse; no mutation during visit.
- **`TreeContext`** = `mounted` (never throws — the staleness probe) + `key`/`branchId`/`dependOnInheritedSeedOfExactType<T>()`/`markNeedsRebuild()`, all throwing `StateError` after unmount (A8, executable). Canonical handle lazily created once per branch via `Branch.context`; `Branch` does NOT implement it.
- **A9 mechanics:** `update(newSeed)` = assert canUpdate → swap seed → `rebuild(force: true)`; dirty flag cleared *before* the hook so a force-rebuilt branch isn't double-built in the same flush. `InheritedBranch.update` notifies dependents BEFORE reconciling its child (Flutter ProxyElement order — keeps builds==1 per provider update).
- **`branchId`**: owner-scoped monotonic decimal string, assigned once at mount (ported verbatim).
- **Node/NodeBranch are NOT lib code** — test fixture only (A11: core is artifact-agnostic); the container artifact lives in `perception`.
- **Flagged, not added:** Flutter's identical-config fast path (`identical(seed, newSeed) → skip`) was deliberately not ported; under A9 every in-place update cascades a subtree rebuild — the const-Seed/short-circuit pruning is the natural next optimization decision. *(Resolved 2026-06-13: A18 ratified to port — the flush inclusion rule above gains the A18 delta on landing.)*
**Affects:** every `tree` consumer; the fast-path question is a future entry. **Status:** promoted → ADR-0001 D5 (tree API surface; the A18 inclusion-rule delta folded in), 2026-06-13 (commit `cc4bf28`).

