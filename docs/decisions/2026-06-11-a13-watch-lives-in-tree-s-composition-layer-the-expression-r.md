---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a13-watch-lives-in-tree-s-composition-layer-the-expression-r
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A13"
---
## A13 (2026-06-11) — Watch lives in tree's composition layer; the expression row stays in genesis  ·  AI

**Decision (defaults presented in the 2026-06-11 discussion, unobjected):** `Watch<T>` (stream → rebuild) moves to `tree`'s composition layer — it is pure composition + dart:async with zero measurement semantics, and it is A5's Attention primitive (substrate). `perception` re-exports/subclasses it. The expression-row packages (wire/actions/terminal, future) stay **in the genesis repo** as sibling packages, consistent with ratified A1 (genesis = shared substrate; the_grid consumes) — not in the_grid.
**Why:** Flutter ships StreamBuilder in the core framework; moving the expression row to the_grid would contradict ratified A1.
**Affects:** `tree` composition-layer contents; ADR-0003/0005 repo placement. **Status:** promoted → ADR-0001 D3 (+ ADR-0003/0005 placement notes), 2026-06-13 (commit `cc4bf28`).

