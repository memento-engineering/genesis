---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a38-domain-authoring-rule-a-component-s-build-must-not-key-a
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by:
    - release-mode-tree-invariants-throw-in-release
  bead: null
  legacy-id: "A38"
---
## A38 (2026-06-15) — Domain authoring rule: a component's `build()` must not key a child with its own A2UI/wire id  ·  AI

**Decision:** a domain component whose branch is keyed by its A2UI wire id (the `buildSeedTree` convention: tree key == component id) must NOT return a child seed keyed with that *same* id from `build()`. Doing so mints a second mounted branch answering to the id, and any id-based lookup — `ConsentRouter.route`'s hit-test — rejects it as ambiguous (the same one-branch-per-id invariant A33 restored for render-scope wrappers, but author-side). Leave component-built children unkeyed, or key them with something distinct from the wire id. `apps/console`'s `Counter` follows this (its `Text` child is unkeyed).
**Why:** discovered building `apps/console` — the A33 e2e proof initially keyed the counter's render child with the counter's own label/id and reproduced the "resolves to N mounted branches" `StateError` *even with A33 fixed*. A33 fixes the framework's render-scope wrapper; this rule covers the orthogonal author-side case the framework cannot fix for the author.
**Affects:** any genesis consumer authoring keyed components (`apps/console`, and the same discipline for `the_grid` / lenny-style domains). Substrate hardening (**now implemented**): a debug `assert` in `tree`'s `updateChildren` (`packages/tree/lib/src/branch.dart`) rejects duplicate non-null sibling keys at reconcile time, naming the offending key — surfacing the collision where it happens rather than as a downstream route ambiguity. Debug-only (tree-shaken in release); unkeyed siblings stay positional and exempt; Flutter parity (`debugCheckUniqueKeys`). Regression test: `packages/tree/test/duplicate_child_key_test.dart`. Pairs with A33. **Status:** pending.

