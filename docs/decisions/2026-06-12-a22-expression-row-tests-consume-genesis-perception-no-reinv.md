---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a22-expression-row-tests-consume-genesis-perception-no-reinv
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A22"
---
## A22 (2026-06-12) — Expression-row tests consume `genesis_perception`; no reinvented fixture vocabularies  ·  decider: Nico

**Decision:** A11's import rule is **one-directional** — `perception` never imports the expression row, but expression-row packages' *tests and demos* consume `genesis_perception` freely (dev dependency). `genesis_typesetting`'s invented fixture types (`Pane`/`Label` in tests, `Panel`/`Readout` in the demo — re-implementations #3 and #4 of the same container/leaf artifact) are **deleted**, replaced by perception's real `Node`/`Field`. The demo (moved `bin/` → `tool/`, dev-dep territory) is now ADR-0004's sleeper win made literal: a live perception tree typeset in the terminal. Typesetting's **lib** stays domain-free — that part of A11 is unchanged.
**Why:** Nico ("very confused why genesis_typesetting decided to invent its own seeds instead of extending") — the reinvention was caused by an over-applied "NO perception dep" constraint in the campaign brief, not by architecture. One vocabulary, consumed where needed; fixtures should *extend* the garden, not fork it. *(Residual instance: `genesis_tree`'s own test fixture Node — it cannot dev-dep on perception without a workspace cycle (perception → tree); that one re-implementation stays, by necessity, and is the canonical non-component-branch example.)*
**Affects:** `genesis_typesetting` tests/demo (corrected, 16/16 green, demo economy unchanged); A20's fixture description; future expression-row packages (`dialogue`/`consent` test against perception vocabulary from day one). **Status:** promoted → ADR-0004 D5 (one-directional import rule; sleeper-win demo), 2026-06-13 (commit `cc4bf28`). *(Superseded in part by A23 — the delegate architecture itself was the disease.)*

