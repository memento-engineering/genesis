---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a27-community-overlap-finding-the-enforce-reject-substrate-i
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A27"
---
## A27 (2026-06-14) — Community-overlap finding: the enforce/reject substrate is genesis-native; a2ui_core has no action-enforcement model  ·  AI

**Finding + recommendation (full analysis: `docs/design/community-overlap-consent.md`).** The STEP-1 check before building `genesis_consent`, covering the action-handling layer A26 explicitly did not (it covered wire/schema/primitives). Examined a2ui_core's `MessageProcessor`/`A2uiClientAction`/`DataModel` and genai_primitives' `ToolDefinition` (flutter/genui @ main, 2026-06-14). **Deciding fact:** a2ui_core has **no action-enforcement model and no element tree to enforce against.** Its `MessageProcessor` handles only the four server→client messages; client actions exit fire-and-forget via a `groupModel.onAction(A2uiClientAction)` listener — no hit-test, no affordance check, no rejection taxonomy. Its component store (`surface.componentsModel`) is a flat `id → ComponentModel` map: `_processUpdateComponents` adds, overwrites props in place, and recreates on a type change (the one `removeComponent` call) — but **never removes a component merely absent from the next emission**, so there is no reconcile-on-absence, no unmount lifecycle, and `staleUnmounted` ("the projection moved", ADR-0005 D3 / the A8 bridge) is **not expressible**. Four sub-findings: (1) `A2uiClientAction` carries dialogue's `ActionEvent` fields verbatim (name/surfaceId/sourceComponentId/timestamp/context) but is **serialize-only** (client *producer*) where dialogue is parse-only (server *receiver*) — two ends of one wire, already aligned in A25, nothing new to adopt; (2) the enforce/reject hit-test against the live Seed/Branch tree + the 4-kind rejection taxonomy + byte-for-byte-untouched + `staleUnmounted` via keyed-reconcile unmount is **genuinely genesis-native — the moat is clearer than A26 assumed, not narrower**; (3) a2ui_core's effect model is **data-binding** (`updateDataModel` → JSON-Pointer `DataModel.set` + `Signal`s + expression evaluator/binder), the deferred dialogue half (A26), NOT an action router — genesis ratified the setState flavor (`perceived()`, ADR-0005 D4) instead; (4) `genai_primitives.ToolDefinition{name, description, inputSchema}` is the agent-loop tool wrapper (right for the whole surface-authoring tool = A26 item 4) but the **wrong granularity** for per-component affordances, which are already catalog-declared (`ActionDeclaration` → `CatalogType.actions` → `x-actions`, A19).
**Recommendation:** (1) build `genesis_consent` as the genesis-native enforce/reject router with **no a2ui_core dependency** — there is no enforcement model to interop with; (2) the only interop surface is the action message vocabulary, **already secured in dialogue (A25)** — a round-trip test against the `A2uiClientAction.toJson()` shape is the cheap conformance check, deferred to ride dialogue's a2ui_core-as-oracle test rather than adding a wip dep; (3) leave `ToolDefinition`/`DataModel` adoption where A26 put them (future agent-loop package / future dialogue data-binding extension); (4) reinforces A26 — consent is a layer a2ui_core structurally cannot offer, the same contribution angle as `genesis_typesetting` for rendering.
**Affects:** `genesis_consent` build direction (this confirms it consumes only genesis seams); ADR-0005 interop note at next promotion; A26 (extends, does not supersede). **Status:** promoted → ADR-0005 D7 (interop), 2026-06-14.

