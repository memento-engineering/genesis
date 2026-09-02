---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a37-one-stage-per-treeowner-multi-component-render-surfaces
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A37"
---
## A37 (2026-06-14) — One Stage per TreeOwner; multi-component render surfaces gated on A33  ·  AI

**Decision:** `StageBranch.attachRenderParent` asserts `owner.onNeedsFlush == null` and that the Stage is not nested — exactly one `Stage` per `TreeOwner`, and it must be the render root. A surface with multiple independently-actionable rendered components therefore needs ONE shared `Stage` above them (a component cannot own its own Stage), which places those components as keyed children of a render container — the A33 case. So "many actionable components on one render surface" is unblocked precisely by A33's fix.
**Why:** documents the constraint surfaced while resolving the console architecture, so future surfaces don't attempt N Stages per owner.
**Affects:** `genesis_typesetting` (single-Stage-per-owner); interacts with A33; apps/console roadmap (multi-component surfaces). **Status:** pending.

