---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a33-render-scope-wrapper-must-not-shadow-the-child-s-key-one
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A33"
---
## A33 (2026-06-14) — Render-scope wrapper must not shadow the child's key (one-branch-per-A2UI-id restored)  ·  AI

**Decision (implemented):** `genesis_typesetting`'s `RenderBranch.renderScopeFor` no longer keys its per-child `InheritedSeed<RenderParentLink>` wrapper with the child's *bare* key; for a keyed child it uses a namespaced `_RenderScopeKey(childKey)` (a distinct, value-equal type), and leaves an unkeyed child's wrapper unkeyed (positional). This restores ADR-0003's "tree key == A2UI id ⇒ exactly one mounted branch per id" invariant that `genesis_consent`'s hit-test (`_mountedMatches`) relies on.
**Why:** `buildSeedTree` sets every component branch's key to its wire id, so the old `key: child.key` minted a *second* mounted branch (the render-scope wrapper) bearing that id whenever any component sat under a render container (`Stage`/`Box`). `ConsentRouter.route` then found 2 branches for one id and threw its DAG-ambiguity `StateError` *before any gate* — making **every** actionable component rendered under a container un-routable, the entire console loop. Invisible to per-package tests because perception's `Node` reconciles children with no wrapper (consent's tests root actionable components under `Node`); the defect lived precisely in the typesetting↔consent seam apps/console is first to cross. All three de-risk spikes + the adversarial skeptic reproduced it (`screen → counter`: matches=2, route throws). The namespaced key keeps the container's keyed reconcile pairing each wrapper with its child across rebuilds/reorders, while the child stays the sole branch answering to its id.
**Considered & rejected:** consent's `_mountedMatches` skipping `InheritedBranchBase` wrappers (smaller, engine untouched, but leaves the invariant violated for any *future* id-keyed consumer); a non-key render-scope mechanism (larger refactor). Fixing at the source restores the invariant for everyone.
**Affects:** `packages/typesetting/lib/src/render_branch.dart` (`renderScopeFor`, new private `_RenderScopeKey`); upholds ADR-0003; unblocks `genesis_consent` routing for components under `Stage`/`Box`. New regression test `packages/typesetting/test/render_scope_key_test.dart` (one-branch-per-key + reorder identity). Typesetting 28 green; full workspace green; analyze + format clean. Ships in `genesis_typesetting` only — needs a `0.1.2` patch to reach pub.dev. **Status:** pending (implemented; Nico to promote → ADR-0003/0004 and approve the patch release).

