---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a12-subclass-mechanics-perception-extends-the-tree-spine-dec
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A12"
---
## A12 (2026-06-11) — Subclass mechanics: perception extends the tree spine  ·  decider: Nico

**Decision:** `Perception extends Seed`; `PerceptionElement extends Branch`; **`PerceptionContext` is a capability extension of `TreeContext`** (the domain layers budget/harvest capabilities onto the handle — handle layering is what A8's separate-handle architecture is for); `PerceptionOwner` builds on `TreeOwner`. Consequence accepted out loud: perception's public signatures surface tree types.
**Why:** Nico's call ("subclass") from the 2026-06-11 ratification discussion; typedefs/wholesale-rename rejected — perception should *be* a tree domain, visibly.
**Affects:** the perception rebuild (A10 campaign); lenny ADR 0001 vocabulary maps onto tree types. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

