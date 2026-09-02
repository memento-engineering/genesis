---
status: accepted
date: 2026-08-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a46-genesis-foundation-is-the-diagnostics-layer-below-the-sp
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A46"
---
## A46 (2026-08-01) — genesis_foundation is the diagnostics layer below the spine · AI

**Decision:** `genesis_foundation` is the dependency-free diagnostics protocol layer below `genesis_tree`; tree depends on and re-exports it, while foundation imports neither tree nor perception. `TreeSnapshot` remains the typed, versioned wire contract in foundation, so out-of-process clients need foundation alone.
**Affects:** `packages/foundation`, `packages/tree`, and diagnostics consumers.
**Status:** PROMOTED (Nico, 2026-08-01) as ADR-0001 Decision 9.

