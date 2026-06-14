# ADR-0003 — A2UI wire format

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A3; *amended 2026-06-14 — the as-built `genesis_dialogue` surface (A25) and the a2ui_core interop posture (A26) promoted (new Decision 5); strict-version + action-field divergences folded into the fidelity ledger.*
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** ADR-0001 Foundations fixes the two-axis model: **authoring** (measurement read-only / expression read-write) × **rendering** (model / machine / human). This ADR fixes the wire format for the *expression* row — the grammar an LLM uses to author and re-emit surfaces, and the grammar genesis uses to serialize them back. Source of truth: register entry **A3** (migrated from lenny A2, rescoped to the authoring axis) plus spike 3 (lenny bead `lenny-f5zn`, green with adversarial verification). **Spike evidence is working-tree-only**: artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md`, `spike3_schema_roundtrip/NOTES.md`, `spike3_flutter_harness/`) and are disposable once genesis lands the real implementation — quoted numbers and paths below are from that tree as of 2026-06-11. The grammar's consumer-side registry is ADR-0002 Schema-first codegen; the action/put half of the loop is ADR-0005 Projection/action substrate.

**The wire package is `genesis_dialogue`.** *Amended 2026-06-13 — promoted from register A17.* The package naming the bidirectional exchange between agent and surface is **`genesis_dialogue`** (replaces the `koine`/`tree_codegen`-era working names): "dialogue" names the structured two-way conversation — the agent authors and re-emits surfaces, the surface reports actions back. Repo placement per register A13 (*amended 2026-06-13 — A13 ratified by Nico*): the wire package stays a sibling package **in the genesis repo** on the expression row, consistent with ratified A1 (genesis = shared substrate; the_grid is a consumer) — it does **not** move to the_grid; `perception` never imports it.

**Status of the package** *(amended 2026-06-14 — A25 promoted).* `genesis_dialogue` is **built**; Decision 5 records the as-built surface. Decisions 1–2 remain the ratified constraints it honors (pure A2UI v0.9; the `genesis_taxonomy` consumption boundary).

---

## Decision 1 — Adopt the A2UI v0.9 flat-keyed grammar, in v0.9 vocabulary (`updateComponents`)

genesis adopts Google **A2UI v0.9**'s flat-list-with-stable-IDs model as both the serialization and the authoring grammar for expression trees. **Spec-name correction folded in on promotion:** the register entry (and the spike handoff) used v0.8's `surfaceUpdate`; spike 3 established against live a2ui.org sources (Message Reference + the v0.9 spec page, consulted 2026-06-11) that **v0.9 renamed `surfaceUpdate` → `updateComponents`**. This ADR and all genesis code use the v0.9 vocabulary.

The wire shape, as mirrored and proven in spike 3:

- **Envelope:** `{"version": "v0.9", "updateComponents": {"surfaceId": ..., "components": [...]}}` — exact field names and nesting.
- **Flat component objects:** string `component` as the type discriminator, all props at the top level of the component object (v0.9's flat style, replacing v0.8's nested `{"component": {"Text": {...}}}`).
- **`children` as ordered arrays of component-id strings** — a flat adjacency list, not nested objects.
- **Root by convention `id == "root"`** — v0.9 has no explicit root field in `updateComponents` (v0.8's `beginRendering.root` was dropped).
- **Action message shape:** `{name, surfaceId, sourceComponentId, timestamp, context}` (a2ui.org) — the client→agent half, carried by ADR-0005's enforce/reject substrate (proven in spike 5), not re-specified here.

**The wire is pure A2UI v0.9.** *Amended 2026-06-13 — promoted from register A19 (the ratified `genesis_taxonomy` as-built confirmed pure v0.9 and bound it as a directive for `genesis_dialogue`).* `genesis_dialogue` MUST honor pure A2UI v0.9: the `updateComponents` envelope (never v0.8's `surfaceUpdate`), and root by the `id == "root"` convention. **The spike's non-standard `rootId` extension is DROPPED** — there is no `rootId` override field; the root is the component whose id is `"root"`, full stop. (`genesis_taxonomy`'s generated tool schema already carries the pure v0.9 `updateComponents` envelope and did **not** carry the spike's `rootId` extension — register A19, as built.)

**Why:** A2UI is purpose-built for LLM incremental/streamed generation, is a framework-agnostic standard (genui/web/Angular), and its stable-ID flat list maps directly onto genesis keyed reconciliation (Decision 3).

## Decision 2 — Wire component IDs are tree keys; `genesis_dialogue` consumes `genesis_taxonomy`'s registry and tool schema

`tree` keys == A2UI component IDs: every component's `id` becomes the mounted node's key (spike: `Perception.key`; genesis: `Seed.key` per ADR-0001 naming). Deserialization goes **exclusively through the generated registry** (ADR-0002): in spike 3, the wire deserializer calls only the generated `buildComponent(type, props, children, key)` — nothing outside the generated wiring hardcodes a component type name, and the same `catalog.json` that generates the registry generates the LLM tool schema for authoring `updateComponents` messages.

**The `genesis_taxonomy` consumption boundary.** *Amended 2026-06-13 — promoted from register A19.* The deserialize half of the loop **already exists in `genesis_taxonomy`**: `buildSeedTree(registry, components, {rootId})` turns a flat `updateComponents` component list into a keyed `Seed` tree (component id → `Seed` key; cycles rejected with the id path; a DAG share built twice), and the generated tool schema is the full pure-v0.9 `updateComponents` envelope (ADR-0002). `genesis_dialogue` therefore **consumes `genesis_taxonomy`** — it does not re-implement deserialization. What `dialogue` adds on top is the remaining wire-loop machinery: the **envelope parse** (validate/extract the `{version, updateComponents:{surfaceId, components}}` outer message), **emission** (serialize a live `Seed`/`Branch` (sub)tree back into an `updateComponents` message), and **reconcile-by-key** (drive the keyed reconciliation of Decision 3 from a deserialized re-emission). (Note: `buildSeedTree` carries a `rootId` parameter as an internal convenience; the **wire** has no `rootId` field — the root is `id == "root"` per Decision 1, A19.)

Malformed wire input is rejected loudly, at the layer that owns the invariant (spike 3 check e, all proven to throw with diagnostics):

- **Deserializer-level (`genesis_taxonomy`):** dangling childId, duplicate id, cycle, missing/ambiguous root (the `id == "root"` component absent).
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

## Decision 5 — The as-built `genesis_dialogue` surface; interop with a2ui_core

*Added 2026-06-14 — promoted from register A25 (`genesis_dialogue` as-built, commit `e0977a3`, 35 tests, two-lens verified) and A26 (the community-overlap finding). Decisions 1–4 set the grammar and constraints; this records the shipped surface and the ratified interop posture.*

**Codec + receive surface (A25).** `parseUpdateComponents(json) → UpdateComponents{surfaceId, components}` + `toJson()`, lossless both ways, reusing `genesis_taxonomy`'s `ComponentInstance` (not redefined). `DialogueSurface` is the receive side: `mount(UpdateComponents)` builds the keyed `Seed` tree via `buildSeedTree` and roots it on an injectable `TreeOwner`; `apply(UpdateComponents)` reconciles a re-emission **by key** (Decision 3), preserving element identity. `parseActionEvent(json) → ActionEvent{name, surfaceId, sourceComponentId, payload, timestamp?}` is **parse-only** — routing / hit-testing / consent is `genesis_consent`'s seam (ADR-0005). Sealed `DialogueException` (envelope + action-message faults); deserialization faults inside the component list stay `genesis_taxonomy`'s `TaxonomyException`.

**Strict version (A25, ratified 2026-06-14).** The `version` field must be present and `== "v0.9"`; a missing field or a v0.8 `surfaceUpdate` message is rejected with `UnsupportedVersionException` — a deliberate divergence from spike 3's lenient parse (fidelity ledger below). This matches a2ui_core's own strictness, so well-formed v0.9 traffic still parses; only missing/wrong is rejected loudly.

**Deferred (out of 1.0):** reverse-emission (a live tree → `updateComponents`) needs a `genesis_taxonomy` reverse-describer that does not exist; the receive + reconcile-by-key path is what ships. `updateDataModel` / data binding, `createSurface` / `deleteSurface` lifecycle, and streaming are likewise deferred — the interop posture below records the adoption path.

**Interop posture — interoperate, don't fork (A26, ratified 2026-06-14).** flutter/genui's lower layers (`a2ui_core`, `json_schema_builder`, `genai_primitives`) are pure-Dart, bare-VM-safe, BSD-3; the Flutter coupling is quarantined in genui's top renderer (the layer `genesis_typesetting`/`genesis_expression` replace), so the substrate bet is **validated, not duplicated**. The one real overlap is the A2UI v0.9 codec (`genesis_dialogue` ↔ `a2ui_core`): genesis's `ActionEvent` / `updateComponents` align field-for-field with a2ui_core's `A2uiClientAction` / `UpdateComponentsMessage`, proven by a conformance test that depends on **no** genui package (`packages/dialogue/test/a2ui_core_conformance_test.dart`). Ratified direction: keep the conformance test now; **adopt `a2ui_core`'s message model once it is ≥ 1.0** (inheriting its `createSurface` lifecycle + `updateDataModel` data binding); **adopt `genai_primitives`** for the agent-loop chat/tool vocabulary when that loop is built; `json_schema_builder` is an optional schema-emit swap. genesis positions as the framework-agnostic renderer + substrate for the A2UI ecosystem. **Do not depend on `a2ui_core` today** (`0.0.1-wip`). Full analysis: `docs/design/community-overlap-genui.md` (A26); the action-handling half is `community-overlap-consent.md` (A27, ADR-0005).

## The fidelity ledger *(accepted practice — Nico, 2026-06-11)*

Register A3 fixes the grammar, not a conformance process; this section records spike evidence plus a standing practice Nico accepted at ratification (2026-06-11). The practice: genesis's A2UI surface carries a standing **fidelity ledger** — spike 3's `NOTES.md` ledger is the model — classifying every spec-relevant behavior as **mirrored** (matches real A2UI v0.9), **diverged** (intentional, documented, with the default that keeps pure v0.9 parsing unchanged), or **unknown** (not yet verified against the spec). A standard adopted without tracking its own divergence silently rots into a dialect; the ledger keeps conformance auditable.

The ledger as of spike 3 (2026-06-11), carried into genesis as the starting state of the accepted practice — *the `rootId` row amended 2026-06-13 (A19 ratified pure v0.9; the extension is dropped, not a standing divergence)*:

| Status | Item |
|---|---|
| Mirrored | Envelope shape; flat components + string `component` discriminator; `children` as ordered id arrays; root by `id == "root"`. |
| Dropped | The spike's optional `rootId` extension field overriding the root convention. *Amended 2026-06-13 (A19, ratified pure v0.9):* the non-standard `rootId` extension is **not carried** — there is no wire `rootId` override; root is `id == "root"`, period. `genesis_taxonomy`'s generated tool schema (as built) did not carry it. |
| Diverged | Component vocabulary is the genesis catalog, not the A2UI standard catalog (`Text`, `Column`, `Button`, …), and the catalog file format is ours, not v0.9 `createSurface.catalogId`'s. *Amended 2026-06-14 (A25, as built):* `version` parsing is now **strict** — present and `== "v0.9"` required (spike 3's lenient parse is not carried); and the client→server `action` message's `timestamp`/`context` are parsed as **optional** where v0.9 marks them required (lenient-in). A DAG share (component reachable via two parents) is built twice rather than rejected; only true cycles are rejected. |
| Deferred | A2UI standard-catalog alignment (the `genesis_dialogue` boundary — register A19); `createSurface` lifecycle; data binding (`/path` data-model references — v0.9's message is named `updateDataModel` per the a2ui.org Message Reference, spike 5 ledger, not v0.8's `dataModelUpdate`); client→server events — out of scope as of the spike, to be ledgered when funded. |
| Unknown | Exact JSON-Schema text of the official v0.9 catalog definitions — the google/A2UI raw schema path (`specification/json/server_to_client.json`) 404'd; field names are as quoted by a2ui.org reference pages. |

---

## Alternatives considered

- **Extend lenny's bespoke Observation JSON into the authoring grammar** — rejected: Observation JSON is the measurement + model-facing cell, purpose-built for *reading* a measurement; A2UI is purpose-built for LLM streamed *generation* and is a standard with independent implementations. Decision 4 keeps both, each in its cell.
- **A dedicated patch/diff-op grammar alongside whole-tree messages** — rejected: spike 3 proves whole-tree emission already reconciles to an identity-preserving patch by key (Decision 3); a second grammar is redundant surface area for the model to misuse.
- **v0.8 vocabulary (`surfaceUpdate`, nested per-type component objects)** — rejected: superseded; spike 3 verified the v0.9 flat shape live against a2ui.org. The register entry's v0.8 naming is corrected by this ADR.
- **Author measurement trees directly (overturn lenny ADR 0001)** — rejected: the read-only rule is the integrity rule of a measurement; the authoring-axis scoping resolves the conflict without touching it.
- **Hand-written wire deserializer with hardcoded type names** — rejected: the generated-registry mediation (Decision 2, ADR-0002) is what makes one `catalog.json` simultaneously the parser, the validator, and the LLM tool schema; hardcoding forks them.

## Register provenance

This document promotes the following ADR-0000 register entries:

- **A3 (2026-06-11) — A2UI flat-keyed grammar as the bidirectional wire format — scoped to the authoring axis** → promoted here in full, with the spike-3 spec correction folded in (v0.9 `updateComponents` replaces the entry's v0.8-era `surfaceUpdate`). A3's status is already `promoted → ADR-0003`.
- **A17 (2026-06-12) — Roadmap package names** → the wire-package name `genesis_dialogue` (the bidirectional-exchange slot) folded into the Context and Decision 2. *(A2/0002 and A5/0005 carry the other two names in their own ADRs.)*
- **A13 (2026-06-11, ratified Nico 2026-06-13) — the expression row stays in genesis** → the repo-placement note folded into the Context (was "pending"; now ratified). *(A13's composition-layer `Watch` half belongs to ADR-0001, not this document.)*
- **A19 (2026-06-12, ratified Nico 2026-06-13) — `genesis_taxonomy` as-built API surface** → the ratified confirmation that the wire is **pure A2UI v0.9 with `rootId` dropped** (binding directive for `genesis_dialogue`), and the `genesis_taxonomy` consumption boundary (`buildSeedTree` + the generated `updateComponents` tool schema), folded into Decisions 1 and 2 and the fidelity ledger. *(A19's primary promotion target is ADR-0002; only its `genesis_dialogue`-binding directives land here.)*

Promoted by the 2026-06-14 pass:

- **A25 (2026-06-13) — `genesis_dialogue` as-built A2UI v0.9 wire surface** → Decision 5 (codec + `DialogueSurface` + `parseActionEvent`; strict version; deferred reverse-emission/data-binding/lifecycle) and the fidelity-ledger Diverged row (strict version + lenient-in action fields).
- **A26 (2026-06-13) — interoperate with flutter/genui's A2UI stack, don't fork it** → Decision 5's interop posture (conformance test now; adopt `a2ui_core`'s message model ≥ 1.0; `genai_primitives` for the agent loop; `json_schema_builder` optional). *(A26's `genai_primitives`/`json_schema_builder` adoption also touches ADR-0002; the consent-side action-handling half is A27/ADR-0005.)*

A7 (grid snapshot-diff vs genesis keyed reconcile) is **closed** in the register (2026-06-14) as out-of-scope here — the_grid's adoption decision belongs in the_grid's ADRs; ADR-0001 Decision 1 / ADR-0004 Decision 6 already disambiguated the reconciler vocabulary.
