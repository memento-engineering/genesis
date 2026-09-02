---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a1-substrate-factoring-the-two-axis-model-decider-nico
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A1"
---
## A1 (2026-06-11) — Substrate factoring + the two-axis model  ·  decider: Nico

**Decision:** `genesis` is the shared engine; `perception` and `the_grid` are domain **consumers**, not owners of the substrate. Repo `memento-engineering/genesis` houses package **`tree`** (the engine — `Seed` config → `Branch` mounted, with `TreeContext` a *separate* handle + `TreeOwner` scheduler — A8, decided 2026-06-11) and package **`perception`** (`Perception`/`PerceptionContext`/`PerceptionOwner`, the measurement domain). Two orthogonal axes govern every projection: **authoring** = measurement (read-only) / expression (read-write); **rendering** = model-facing (serialize, no geometry) / machine-facing (typed structs) / human-facing (render tree, 2-D geometry).
**Why:** resolves the perception↔grid "one substrate or two?" question — neither; genesis is the root both build on. The two axes dissolve the apparent conflicts in A3 and A4: each is a different cell of the 2-axis space, and lenny's ADR 0001 occupied exactly one cell (measurement + model-facing), correctly.
**Affects (if promoted):** seed of a genesis ADR-0001 (foundations); repo/package layout; lenny ADR 0001/0002 (perception) migrate here when the code moves.
**Origin:** lenny conversation 2026-06-11. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

