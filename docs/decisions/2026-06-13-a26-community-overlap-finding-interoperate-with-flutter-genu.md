---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a26-community-overlap-finding-interoperate-with-flutter-genu
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A26"
---
## A26 (2026-06-13) — Community-overlap finding: interoperate with flutter/genui's A2UI stack, don't fork it  ·  AI

**Finding + recommendation (full analysis: `docs/design/community-overlap-genui.md`).** genui's lower layers — `a2ui_core`, `json_schema_builder`, `genai_primitives` — are **pure-Dart, bare-VM-safe, BSD-3, `labs.flutter.dev`**; the Flutter coupling is quarantined in the top-level `genui` renderer (the layer `genesis_typesetting`/`genesis_expression` replace), so the substrate bet is **validated, not duplicated**. Overlap is narrow: `genesis_dialogue` ↔ **`a2ui_core`** (the A2UI v0.9 codec — we rebuilt it); `genesis_taxonomy` ↔ `json_schema_builder` (orthogonal — only schema-emit/validate overlaps; our catalog→registry codegen has no counterpart); **`genai_primitives` = a gap** (the conversation/tool vocabulary we'll need and don't have); `tree`/`perception`/`typesetting` = no equivalent.
**Recommendation:** (1) **conformance-adapter + interop test against `a2ui_core` now** (catches the `id=="root"` vs surface-envelope drift) without depending on a `0.0.1-wip` package; (2) post-stable (a2ui_core ≥ 1.0), collapse `dialogue` to the reconcile-onto-tree adapter and **depend on `a2ui_core`'s message model** — inheriting its `createSurface` lifecycle + `updateDataModel` data binding we deferred; (3) optionally adopt `json_schema_builder` for schema emission (ecosystem-aligned, modest); (4) **adopt `genai_primitives`** for the agent-loop vocabulary when built; (5) reposition genesis as the framework-agnostic renderer + substrate for the A2UI ecosystem (`genesis_typesetting` is a bare-VM A2UI renderer genui can't offer — a contribution angle). **Do NOT depend on `a2ui_core` today** (wip, 1 like, `preact_signals`).
**Affects:** `genesis_dialogue` (A25) future shape; `genesis_taxonomy` schema-emit; a future agent-loop package; ADR-0003 interop note at next promotion. Beads `genesis-` (interop adapter / genai_primitives / json_schema_builder). **Status:** promoted → ADR-0003 D5 (interop posture), 2026-06-14.

