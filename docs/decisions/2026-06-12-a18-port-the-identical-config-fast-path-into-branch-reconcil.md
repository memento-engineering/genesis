---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a18-port-the-identical-config-fast-path-into-branch-reconcil
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A18"
---
## A18 (2026-06-12) — Port the identical-config fast path into `Branch` reconciliation, as `identical()` — never `==`  ·  AI

**Decision (proposed; analysis at `docs/design/a9-fast-path-analysis.md`, bead `genesis-ak7`):** `Branch.updateChild` and `Branch.updateChildren` skip the in-place update when `identical(child.seed, newSeed)` — no `update()`, no force-rebuild, no cascade. Ports Flutter `Element.updateChild`'s fast path with three genesis refinements: (1) the check is written `identical()` explicitly and `Seed.operator==` stays **unpinned** (free for future freezed value-equality without ever affecting reconcile — Flutter instead forbids overriding `Widget.==`); (2) `updateChildren` refactored to delegate pairs to `updateChild` (Flutter's own shape) so there is a single skip site; (3) no slot handling because `Branch` stores no slot — **recorded obligation:** when render branches grow slots, the skip must update slots on move per Flutter's `updateSlotForChild`. `Branch.update` itself keeps A9 force semantics; the skip is reconciliation-only.
**Provider correctness (verified by reading):** invalidation is independent of the cascade (`InheritedBranch.update` notifies dependents BEFORE child reconcile; `dependencyChanged → markNeedsRebuild` flows through the owner dirty set; mid-flush-dirtied branches rebuild in the same pass). Delta to A14's flush inclusion rule: a dependent under a skipped subtree now rebuilds at drain time and is **INCLUDED in `flush()`'s returned list** (previously cascade-force-rebuilt and excluded — strictly better render-backend reporting). Out-of-flush provider updates with an identical child rebuild dependents at the next `flush()` instead of synchronously.
**Why:** A14 flagged it; under A9 provider updates are O(subtree) instead of O(dependents) and const-Seed pruning is defeated; A4's dirty-region economics require static subtrees to short-circuit. **Honest limit:** the wire path gains nothing — deserialized A2UI seeds are never `identical()`; wire-cost containment belongs in `genesis_dialogue` key/payload diffing (a `==`-based skip was considered and rejected).
**Affects:** `packages/tree/lib/src/branch.dart`; A14 inclusion-rule wording; ADR-0001 Decision 4 gains an "unless identical" clause at promotion; perception inherits (conformance suite is the gate). Ten gating tests proposed in the analysis doc. **Status:** **ratified + LANDED (commit `4daada8`, 2026-06-13).** Single skip site (`updateChildren` delegates to `updateChild`); `Seed.==` unpinned; `Branch.update` keeps A9 force semantics; no slot handling (deferred obligation recorded in the `updateChild` doc comment). 11 gating tests; tree 109→120, perception 104 unchanged; verifier confirmed with three tamper probes. A14 inclusion-rule delta folded in above. Bead `genesis-4m1` closed. **Promoted → ADR-0001 D4 ("unless identical" clause) + D5 (inclusion delta), 2026-06-13 (commit `cc4bf28`).**

