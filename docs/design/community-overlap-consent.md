# Community overlap: flutter/genui's action-handling vs. genesis_consent

**Date:** 2026-06-14 · **Status:** findings + recommendation (register A27, pending Nico)

STEP-1 check before building `genesis_consent` (bead `genesis-hjj`, the
enforce/reject action router of ADR-0005). consent is the **highest
community-overlap-risk** package of the original arc: the prior genui research
(`community-overlap-genui.md`, register A26) covered the wire/schema/primitives
but explicitly **not** the action-handling/enforcement model. Per A26
(interoperate, don't fork), this examines a2ui_core's client→server action path
and genai_primitives' tool vocabulary before the router is written.

## The deciding fact

**a2ui_core has no action-enforcement model and no element tree to enforce
against.** Its `MessageProcessor` processes only the four **server→client**
messages (createSurface / updateComponents / updateDataModel / deleteSurface).
Client actions never enter the processor — they exit it, fire-and-forget,
through a single listener (`groupModel.onAction(A2uiClientAction)`). There is no
hit-test, no affordance check, no rejection taxonomy, and — because its
component store is a flat additive map with no unmount lifecycle — no way to
detect that "the projection moved under the actor." The enforce/reject substrate
ADR-0005 specifies is genuinely genesis-native; the moat is *clearer* than A26's
prior assumed, not narrower.

## What was examined (as found, flutter/genui @ main, 2026-06-14)

- `a2ui_core/lib/src/core/messages.dart` — the message vocabulary incl.
  `A2uiClientAction`.
- `a2ui_core/lib/src/processing/processor.dart` — `MessageProcessor`, the
  central message handler.
- `a2ui_core/lib/src/core/data_model.dart` — the reactive `DataModel`
  (JSON-Pointer store + `Signal`s).
- `a2ui_core/lib/src/processing/{expressions,basic_functions}.dart`,
  `rendering/binder.dart` — the expression evaluator + prop binder (surveyed).
- `genai_primitives/lib/src/tool_definition.dart` — `ToolDefinition`.

## Finding 1 — the action message vocabulary is identical, and complementary

`A2uiClientAction` carries exactly genesis dialogue's `ActionEvent` fields:
`name`, `surfaceId`, `sourceComponentId`, `timestamp`, `context`. dialogue (A25)
already aligned to this field-for-field. The one structural distinction is
**direction**:

| | a2ui_core `A2uiClientAction` | genesis dialogue `ActionEvent` |
|---|---|---|
| Codec | `toJson()` only — **serialize** | `parseActionEvent` — **parse** |
| Role | the **client** *emitting* the action | the **server** *receiving* it |
| `timestamp` | `DateTime`, required | `String?`, optional (carried verbatim) |
| `context` | `Map`, required | `Map`, defaults `{}` |

These are the two ends of one wire, not two implementations of the same thing.
a2ui_core produces the action a client sends; dialogue decodes the action a
server receives; consent routes/enforces it. **Nothing to adopt — the alignment
is already secured in dialogue.** A round-trip test (feed an
`A2uiClientAction.toJson()` shape through `parseActionEvent`) is the cheap
conformance check, mirroring dialogue's a2ui_core-as-oracle recommendation; it
needs no dependency on the wip package.

## Finding 2 — a2ui_core cannot express the enforce/reject hit-test (the moat)

Two structural gaps make ADR-0005's substrate impossible to express in
a2ui_core, so it is genuinely ours to build:

1. **No enforcement path for actions.** `MessageProcessor` has no
   `_processAction`; `A2uiClientAction` reaches the host only via the
   `onAction` listener. No gate, no validation, no structured rejection. The
   four-kind rejection taxonomy (`unknownComponent` / `staleUnmounted` /
   `undeclaredAction` / `badPayload`) and the byte-for-byte-untouched-on-reject
   guarantee have no counterpart.
2. **No element tree, no unmount, no staleness.** a2ui_core's "tree" is
   `surface.componentsModel`, a flat `id → ComponentModel(id, type, props)`
   map. `_processUpdateComponents` is **additive/mutating only**: it adds new
   components, overwrites props in place, recreates on a type change — and
   **never removes** a component absent from the new emission. There is no
   keyed reconcile, no mount/unmount lifecycle, no element identity. Therefore
   `staleUnmounted` — "the projection moved under the actor" (ADR-0005
   Decision 3, the A8 async-gap bridge) — is **not expressible**: nothing ever
   gets unmounted, so a previously-valid intent can never be detected as
   pointing at a vanished component.

genesis hit-tests a previously valid intent against the **live** Seed/Branch
tree, walked fresh per route call (no cached refs — the A8 rule). Keyed
reconcile unmounts exactly the removed component while survivors keep identity
*and* live state, which is precisely what makes `staleUnmounted` a first-class,
distinguishable outcome. a2ui_core has none of this substrate.

## Finding 3 — a2ui_core's effect model is data-binding, not setState

Where a2ui_core *does* push effects to the UI, it does so via `updateDataModel`
(`DataModel.set(path, value)` over JSON Pointer + reactive `Signal`s) and an
expression evaluator / binder that recompute bound props. This is a
**server→client state-push + reactive recompute** model — the very
`updateDataModel`/data-binding path dialogue **deferred** (A25). It is *not* an
action-enforcement router. ADR-0005 ratified the opposite flavor: enforce
through the target State's `perceived()` (setState; Decision 4), with the
existing dirty/flush pipeline doing exactly-the-target-subtree invalidation.
Two different philosophies; consent implements the ratified one.

Note for the roadmap: a2ui_core's `DataModel` + `Signal`s is the natural
long-term home for **dialogue's deferred data-binding half**, not for consent.
That stays an A26 dialogue concern.

## Finding 4 — ToolDefinition is the agent-loop wrapper, wrong granularity for affordances

`genai_primitives.ToolDefinition{name, description, inputSchema (JSON Schema)}`
is the LLM tool-call vocabulary. It is the right wrapper for the **whole
surface-authoring tool** — taxonomy's emitted `updateComponents` schema is
exactly a `ToolDefinition.inputSchema` — which is A26 item 4's future
agent-loop adoption. It is the **wrong granularity for per-component affordance
declaration**: consent's affordances are catalog-declared per type
(`ActionDeclaration{name, description}` → `CatalogType.actions` → the `x-actions`
tool-schema keyword), already built in `genesis_taxonomy` (A19). consent
**consumes** that channel and needs no new vocabulary. ToolDefinition belongs
to the future agent-loop package, not consent.

## Adopt / keep split

| Layer | Verdict |
|---|---|
| Action message vocabulary (`ActionEvent` ↔ `A2uiClientAction`) | **Interop — already aligned in dialogue (A25).** Two ends of one wire. Add a round-trip test; no dependency. |
| Enforce/reject hit-test vs the live Seed/Branch tree + `x-actions` affordances; 4-kind rejection taxonomy; byte-for-byte-untouched; `staleUnmounted` (A8 bridge); enforce via `perceived()` | **Genesis-native — the moat.** a2ui_core has no element tree, no lifecycle, no rejection model. Build it here. |
| Reactive `DataModel` + expressions + binder | **Not consent's.** It is the data-binding alternative to setState-enforcement and the home for dialogue's deferred `updateDataModel` half (A26 dialogue concern). |
| `ToolDefinition` | **Not consent's.** Agent-loop wrapper (A26 item 4); wrong granularity for affordances. |
| Multi-party consensus | **Parked, lean LWW** (ADR-0005 Decision 6; spike-5 probe). Unchanged. |

## Recommendation — build native; the only interop surface is the wire, already secured

1. **Build `genesis_consent` as the genesis-native enforce/reject router with no
   a2ui_core dependency.** There is no enforcement model in a2ui_core to interop
   with — the substrate is exclusively ours.
2. **The only interop surface is the action message vocabulary, already secured
   in dialogue (A25).** A consent-level round-trip test against the
   `A2uiClientAction.toJson()` shape is the cheap conformance check; defer it to
   ride dialogue's a2ui_core-as-oracle test rather than adding a wip dependency.
3. **Leave ToolDefinition / DataModel where A26 put them** — the future
   agent-loop package (ToolDefinition) and a future data-binding extension to
   dialogue (DataModel). Neither is consent's concern.
4. **Reinforces A26:** genesis is the framework-agnostic substrate for the A2UI
   ecosystem. consent is a layer a2ui_core structurally *cannot* offer, because
   it has no element tree to enforce against — the same contribution-angle story
   as `genesis_typesetting` for rendering.

## Sources

flutter/genui @ `main` (raw contents API, 2026-06-14):
`packages/a2ui_core/lib/src/core/messages.dart`,
`.../processing/processor.dart`, `.../core/data_model.dart`;
`packages/genai_primitives/lib/src/tool_definition.dart`. Prior analysis:
`docs/design/community-overlap-genui.md` (register A26).
