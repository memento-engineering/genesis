# ADR-0003 — A2UI wire format

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A3
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** ADR-0001 Foundations fixes the two-axis model: **authoring** (measurement read-only / expression read-write) × **rendering** (model / machine / human). This ADR fixes the wire format for the *expression* row — the grammar an LLM uses to author and re-emit surfaces, and the grammar genesis uses to serialize them back. Source of truth: register entry **A3** (migrated from lenny A2, rescoped to the authoring axis) plus spike 3 (lenny bead `lenny-f5zn`, green with adversarial verification). **Spike evidence is working-tree-only**: artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md`, `spike3_schema_roundtrip/NOTES.md`, `spike3_flutter_harness/`) and are disposable once genesis lands the real implementation — quoted numbers and paths below are from that tree as of 2026-06-11. The grammar's consumer-side registry is ADR-0002 Schema-first codegen; the action/put half of the loop is ADR-0005 Projection/action substrate. Repo placement per register A13 (pending): the wire package stays a sibling package in the genesis repo on the expression row; `perception` never imports it.

---

## Decision 1 — Adopt the A2UI v0.9 flat-keyed grammar, in v0.9 vocabulary (`updateComponents`)

genesis adopts Google **A2UI v0.9**'s flat-list-with-stable-IDs model as both the serialization and the authoring grammar for expression trees. **Spec-name correction folded in on promotion:** the register entry (and the spike handoff) used v0.8's `surfaceUpdate`; spike 3 established against live a2ui.org sources (Message Reference + the v0.9 spec page, consulted 2026-06-11) that **v0.9 renamed `surfaceUpdate` → `updateComponents`**. This ADR and all genesis code use the v0.9 vocabulary.

The wire shape, as mirrored and proven in spike 3:

- **Envelope:** `{"version": "v0.9", "updateComponents": {"surfaceId": ..., "components": [...]}}` — exact field names and nesting.
- **Flat component objects:** string `component` as the type discriminator, all props at the top level of the component object (v0.9's flat style, replacing v0.8's nested `{"component": {"Text": {...}}}`).
- **`children` as ordered arrays of component-id strings** — a flat adjacency list, not nested objects.
- **Root by convention `id == "root"`** — v0.9 has no explicit root field in `updateComponents` (v0.8's `beginRendering.root` was dropped).
- **Action message shape:** `{name, surfaceId, sourceComponentId, timestamp, context}` (a2ui.org) — the client→agent half, carried by ADR-0005's enforce/reject substrate (proven in spike 5), not re-specified here.

**Why:** A2UI is purpose-built for LLM incremental/streamed generation, is a framework-agnostic standard (genui/web/Angular), and its stable-ID flat list maps directly onto genesis keyed reconciliation (Decision 3).

## Decision 2 — Wire component IDs are tree keys, mediated by the generated registry

`tree` keys == A2UI component IDs: every component's `id` becomes the mounted node's key (spike: `Perception.key`; genesis: `Seed.key` per ADR-0001 naming). Deserialization goes **exclusively through the generated registry** (ADR-0002): in spike 3, the wire deserializer calls only the generated `buildComponent(type, props, children, key)` — nothing outside `registry.g.dart` hardcodes a component type name, and the same `catalog.json` that generates the registry generates the LLM tool schema for authoring `updateComponents` messages.

Malformed wire input is rejected loudly, at the layer that owns the invariant (spike 3 check e, all proven to throw with diagnostics):

- **Deserializer-level:** dangling childId, duplicate id, cycle, unknown rootId.
- **Generated-registry-level:** unknown type, mistyped prop, missing required prop, children on a leaf.

The checks are framework-free (`lib/checks.dart` imports no test framework) and the identical five check functions run green under `dart test` on the bare VM **and** under `flutter test` (Flutter 3.44.0, Dart 3.12.0) — the grammar is binding-agnostic by construction.

## Decision 3 — Whole-(sub)tree emission IS the patch: identity-preserving reconcile by key

There is **no "whole tree vs patch" fork** at the wire level. The model re-emits whatever granularity is convenient — a whole surface or a subtree — and keyed reconciliation derives the identity-preserving patch. Spike 3 check (d) is the executable demonstration: mount v1 (root + 4 keyed children including a nested subtree), capture the live element instances, deserialize a whole-tree v2 re-emission (one prop changed, one component removed, one inserted, two reordered), update the root, and assert with `identical()`:

- `f_name` (prop changed) → **same element instance**, new config object, new prop value visible;
- `n_addr` (index 2→1) and `f_email` (1→2), reordered → **same instances** at their new indices;
- **deep identity:** `f_street`, nested inside the *moved* `n_addr` subtree, is also the **same instance**;
- `f_age` (removed) → old instance unmounted (`.mounted == false`);
- `f_phone` (inserted) → fresh, mounted instance.

The root survives re-emission because `"root"` (the v0.9 convention) is a stable key and `canUpdate` holds. ADR-0001's rebuild rule (register A9: a config update re-runs the builder) is orthogonal — element-identity preservation, the crux here, holds either way.

**Consequence:** the LLM never computes diffs; the serializer never speaks a second grammar; subscriptions, focus, and accumulated state riding on element identity survive re-emission. Deliberately not proven (per `RESULTS.md`): measured patch byte-*minimality* — identity preservation is proven, byte minimality implied.

## Decision 4 — Scope: the authoring axis only; lenny ADR 0001 stays intact

Authoring is a property of the tree's **role**, not the engine. **Measurement trees stay read-only** — lenny ADR 0001's "the model never constructs Perceptions" is the *integrity rule of a measurement*: the model's only `put` is a hit-tested action on the world, after which the tree re-measures. **Expression trees (surfaces) are authored directly**, and A2UI authoring lives on that expression row. Lenny ADR 0001's bespoke Observation JSON is not replaced — it remains the measurement + model-facing cell of the two-axis grid. Scoping by authoring role *bounds* the apparent "revisits 0001" tension rather than overturning the rule.

## The fidelity ledger *(accepted practice — Nico, 2026-06-11)*

Register A3 fixes the grammar, not a conformance process; this section records spike evidence plus a standing practice Nico accepted at ratification (2026-06-11). The practice: genesis's A2UI surface carries a standing **fidelity ledger** — spike 3's `NOTES.md` ledger is the model — classifying every spec-relevant behavior as **mirrored** (matches real A2UI v0.9), **diverged** (intentional, documented, with the default that keeps pure v0.9 parsing unchanged), or **unknown** (not yet verified against the spec). A standard adopted without tracking its own divergence silently rots into a dialect; the ledger keeps conformance auditable.

The ledger as of spike 3 (2026-06-11), carried into genesis as the starting state of the accepted practice:

| Status | Item |
|---|---|
| Mirrored | Envelope shape; flat components + string `component` discriminator; `children` as ordered id arrays; root by `id == "root"`. |
| Diverged | Optional `rootId` extension field overriding the root convention (defaults to `"root"`; pure v0.9 messages parse unchanged). Component vocabulary is the genesis catalog, not the A2UI standard catalog (`Text`, `Column`, `Button`, …), and the catalog file format is ours, not v0.9 `createSurface.catalogId`'s. `version` parsed leniently. A DAG share (component reachable via two parents) is built twice rather than rejected; only true cycles are rejected. |
| Deferred | `createSurface` lifecycle; data binding (`/path` data-model references — v0.9's message is named `updateDataModel` per the a2ui.org Message Reference, spike 5 ledger, not v0.8's `dataModelUpdate`); client→server events — out of scope as of the spike, to be ledgered when funded. |
| Unknown | Exact JSON-Schema text of the official v0.9 catalog definitions — the google/A2UI raw schema path (`specification/json/server_to_client.json`) 404'd; field names are as quoted by a2ui.org reference pages. |

---

## Alternatives considered

- **Extend lenny's bespoke Observation JSON into the authoring grammar** — rejected: Observation JSON is the measurement + model-facing cell, purpose-built for *reading* a measurement; A2UI is purpose-built for LLM streamed *generation* and is a standard with independent implementations. Decision 4 keeps both, each in its cell.
- **A dedicated patch/diff-op grammar alongside whole-tree messages** — rejected: spike 3 proves whole-tree emission already reconciles to an identity-preserving patch by key (Decision 3); a second grammar is redundant surface area for the model to misuse.
- **v0.8 vocabulary (`surfaceUpdate`, nested per-type component objects)** — rejected: superseded; spike 3 verified the v0.9 flat shape live against a2ui.org. The register entry's v0.8 naming is corrected by this ADR.
- **Author measurement trees directly (overturn lenny ADR 0001)** — rejected: the read-only rule is the integrity rule of a measurement; the authoring-axis scoping resolves the conflict without touching it.
- **Hand-written wire deserializer with hardcoded type names** — rejected: the generated-registry mediation (Decision 2, ADR-0002) is what makes one `catalog.json` simultaneously the parser, the validator, and the LLM tool schema; hardcoding forks them.

## Register provenance

This document promotes exactly one ADR-0000 register entry:

- **A3 (2026-06-11) — A2UI flat-keyed grammar as the bidirectional wire format — scoped to the authoring axis** → promoted here in full, with the spike-3 spec correction folded in (v0.9 `updateComponents` replaces the entry's v0.8-era `surfaceUpdate`). On ratification, flip A3's status to `promoted → ADR-0003`.

No other entries are promoted by this document. A7 (grid snapshot-diff vs genesis keyed reconcile) remains open in the register and is deliberately untouched.
