---
status: accepted
date: 2026-08-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a48-diagnosticable-hooks-take-a-diagnosticsbuilder-decider-n
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A48"
---
## A48 (2026-08-01) — Diagnosticable hooks take a DiagnosticsBuilder · decider: Nico

**Decision:** `Diagnosticable.debugFillProperties` and `DiagnosticableTree` implementations take a `DiagnosticsBuilder`, superseding the bare `List<DiagnosticsProperty>` signature. The builder is Flutter-faithful in mechanism and leaves evolution room for context such as style hints, filtering, and deduplication without another hook signature break. The `TreeSnapshot`/`DiagnosticsProperty` version-1 wire contract is unchanged, and ADR-0001 Decision 9's foundation-below-tree layering is unchanged.
**Affects:** `packages/foundation`, `packages/tree`, and `packages/perception`; breaking package releases `0.2.0`.
**Status:** Ratified (Nico, 2026-08-01, live ruling; governor relayed).
