---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a3-a2ui-flat-keyed-grammar-as-the-bidirectional-wire-format
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A3"
---
## A3 (2026-06-11) — A2UI flat-keyed grammar as the bidirectional wire format — *scoped to the authoring axis*  ·  AI

*(migrated from lenny A2; rescoped + retagged scoped)*
**Decision:** adopt Google **A2UI** (v0.9) flat-list-with-stable-IDs model (`surfaceUpdate`/`dataModelUpdate`/`action`) as both the serialization and the emission grammar; `tree` keys == A2UI component IDs; whole-(sub)tree emission reconciles to a patch by key (no "whole tree vs patch" fork).
**Scope (resolves the apparent 0001 conflict):** authoring is a property of the tree's *role*, not the engine. **Measurement** trees stay read-only — lenny ADR 0001's "the model never constructs Perceptions" is the *integrity rule of a measurement*: the model's only `put` is a hit-tested action on the world, after which the tree re-measures. **Expression** trees (surfaces) are authored directly. genesis supports both; A2UI authoring lives on the expression row, leaving 0001 intact for perception.
**Why:** A2UI is purpose-built for LLM incremental/streamed generation, is a framework-agnostic standard (`genui`/web/Angular), and maps onto genesis keyed reconciliation. Scoping by authoring-role bounds the "revisits 0001" tension rather than overturning it.
**Affects:** lenny ADR 0001's bespoke Observation JSON (now the measurement+model-facing cell); a serializer + a deserialize/reconcile path in `tree`. **Status:** promoted → ADR-0003 (ratified Nico 2026-06-11; v0.9 `updateComponents` vocabulary adopted; fidelity-ledger practice accepted by Nico).

