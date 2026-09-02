---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a25-genesis-dialogue-as-built-a2ui-v0-9-wire-surface-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A25"
---
## A25 (2026-06-13) — `genesis_dialogue` as-built A2UI v0.9 wire surface  ·  AI

**Decision (as built, commit `e0977a3`; 35 tests, two-lens verified — the fidelity skeptic independently re-fetched a2ui.org and confirmed the envelope + action fields verbatim):**
- **Codec:** `parseUpdateComponents(json) → UpdateComponents{surfaceId, components: List<ComponentInstance>}` + `toJson()`, lossless both ways. Reuses `genesis_taxonomy`'s `ComponentInstance` (imported, not redefined). Pure A2UI v0.9: `updateComponents` envelope, flat components, string `component` discriminator, top-level props, `children` as ordered id arrays, root by `id=="root"`, **NO `rootId`**.
- **`DialogueSurface{registry (injected `ComponentRegistry`), owner (injectable `TreeOwner`)}`:** `mount(UpdateComponents)` → `buildSeedTree` → `owner.mountRoot`; `apply(UpdateComponents)` → `rootBranch.update(newRootSeed)` keyed reconcile (component id == Seed key; identity preserved — verified with `identical()` incl. deep identity in a moved subtree, removed unmounts, inserted fresh). Registry-agnostic; a renderer (`typesetting`/`expression`) shares the injected owner.
- **`parseActionEvent(json) → ActionEvent{name, surfaceId, sourceComponentId, payload(=context), timestamp?}`** — **PARSE ONLY**; routing / hit-test / enforce-reject is `genesis_consent`'s seam (no tree mutation in dialogue). The decoded-not-authorized event is what consent consumes.
- **Sealed `DialogueException`** (EnvelopeException + ActionMessageException); envelope-level structural faults only — dangling-childId / unknown-type / cycle stay `genesis_taxonomy`'s `TaxonomyException` (not duplicated).
- **Version strictness = STRICT** (must be present and `=='v0.9'`); deliberate divergence from spike 3's lenient parse, ledgered (real v0.9 messages always carry the version, so still parse; only missing/wrong is rejected loudly).
- Test catalog binds `node`/`field` → `genesis_perception` `Node`/`Field` (A22); committed `.g.dart`/`.g.json` with an in-sync guard.
**Deferred (v1 boundaries, ledgered):** Seed-tree→envelope **reverse-emission** (needs a taxonomy reverse-describer that does not exist — flagged, not built, taxonomy untouched); action **routing → `genesis_consent`**; `updateDataModel` / data binding; `createSurface` lifecycle; streaming/incremental. The A18 fast path is honestly **inert on the wire path** (deserialized seeds are never `identical()`) — keyed identity preservation is the point and holds.
**Keeper-flagged tidy (fidelity skeptic, non-blocking):** the README ledger records the strict-version + action-nesting divergences but NOT that action `timestamp`/`context` are parsed as optional where v0.9 marks them required — add that "Diverged" row in a tidy pass to keep the ledger honest.
**Affects:** ADR-0003 at next promotion; `genesis_consent` consumes `ActionEvent` + the live surface; renderers mount the injected owner. **Status:** promoted → ADR-0003 D5, 2026-06-14.

