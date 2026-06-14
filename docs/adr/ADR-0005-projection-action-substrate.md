# ADR-0005 — Projection/action substrate: four dynamics, four audiences, enforce/reject

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A5 (multi-party consensus explicitly NOT promoted — parked, lean last-write-wins); *amended 2026-06-14 — the as-built `genesis_consent` surface (A28), the `@protected`-state / element action-seam (A30), and the action-handling interop finding (A27) promoted (new Decision 7).*
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** ADR-0001 (Foundations) fixes the engine (`Seed`/`Branch`/`TreeContext`/`TreeOwner`) and the two-axis model; ADR-0002 (Schema-first codegen) fixes how the node catalog becomes both a Dart registry and an LLM tool schema; ADR-0003 (A2UI wire format) fixes the bidirectional grammar; ADR-0004 (Render backends) fixes how one tree renders to many audiences. This ADR names the *manipulation* half: what it means for any party — model, human, or code — to act on a projected tree, and what the framework does when the act is valid or invalid. It promotes register entry A5 and unparks the half lenny ADR 0001 explicitly parked ("Decisions & forks" §3, the action/affordance half — `com.nicospencer/lenny/docs/adrs/0001-declarative-perception-framework.md`). Every claim below is grounded in spike 5 (`spike5_action_roundtrip`, bead `lenny-78r1`): 9 tests green on the bare VM (`dart test`, Dart 3.12.0), adversarially verified. **Evidence is working-tree-only:** the spike artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md` + `spike5_action_roundtrip/NOTES.md`) per the spike-first constraint — disposable reference evidence once genesis lands the real thing.

*Amended 2026-06-13 — promoted from register A17. The action router this ADR describes is named **`genesis_consent`** (faculty-naming per A16: affordances declare what may be asked; the router grants or withholds; every rejection kind is a refusal of consent, and `staleUnmounted` is consent *revoked* because the world changed). It is the expression-row sibling package that **consumes `genesis_taxonomy`'s catalog-declared action affordances** (the `x-actions` keyword the extension seam emits — A19's `ActionsCatalogExtension`) and **routes intents back over the `genesis_dialogue` wire** (the A2UI grammar of ADR-0003). `genesis_consent` is now **built** (Decision 7 records the as-built surface, promoted 2026-06-14); this Context recorded the ratified direction and the consume-relationships; the enforce/reject = hit-testing framing and the parked last-write-wins consensus lean below are unchanged.*

---

## Decision 1 — Interfaces are projections; four dynamics, bound to the tree vocabulary

Frame the whole system as **interfaces-as-projections**: a `get` projection plus `put` handles. Four dynamics, each bound to a concrete mechanism already in the tree vocabulary — none of them new machinery:

| Dynamic | Is | Mechanism |
|---|---|---|
| **Context** | the projection itself | the mounted tree, rendered per the ADR-0001 rendering axis (serialize / typed structs / render tree — ADR-0004) |
| **Attention** | what the projection tracks | the subscription graph (`Watch`) — plus the focus-policy knob (lenny ADR 0001's ambient `PerceptionPolicy`), which **stays parked**; only the binding is promoted here. Per register A13 (ratified Nico 2026-06-13), `Watch` **lives in** `tree`'s composition layer — the Attention primitive is substrate-level — with `perception` re-exporting it (ADR-0001 Decision 3). |
| **Affordance** | what the projection can be asked to do | **catalog-declared actions** — `genesis_taxonomy`'s per-type `actions` map (the `x-actions` keyword its `ActionsCatalogExtension` seam emits, register A17/A19) — and as of spike 5 they are *executable*, not aspirational: the catalog's per-type `actions` map flows into the generated tool schema (an `x-actions` keyword on the button variant plus prose in the variant description), so an LLM reading only the tool schema discovers which components afford which actions and how to address them (`sourceComponentId`, `"press"`). Non-actionable types (label, panel) declare nothing. One catalog is simultaneously the affordance declaration the LLM sees and the affordance check the router (`genesis_consent`) enforces (`componentActions` + `wireTypeOfPerception` in the generated `actions.g.dart`) — the ADR-0002 one-schema property, extended to actions. |
| **Intent** | the thing the framework does **not** supply | brought by the actor — model, human, or code. The framework projects and enforces; it never wants. |

This names what lenny ADR 0001 §3 half-formalized and parked ("dynamic, state-derived tool lists harvested from the tree"), and generalizes single-app-observe into a multi-party substrate.

## Decision 2 — Validation/invalidation = enforce/reject; action validation IS hit-testing

An incoming intent (A2UI v0.9 `action` message: `{name, surfaceId, sourceComponentId, timestamp, context}`) is validated by **hit-testing the live mounted tree** — lenny ADR 0001's "action validation == hit-testing" line, now executable. Spike 5's router (`spike5_action_roundtrip/lib/action_router.dart`) gates in three catalog/tree-derived steps, none hardcoded:

1. **exists/mounted** — `sourceComponentId` resolves to a MOUNTED element by walking the live tree *fresh on every route call* (no cached element refs);
2. **catalog-declared** — the live element's catalog type declares the action name, looked up in generated catalog-derived data, so the affordance check and the LLM-visible affordance declaration share one source of truth;
3. **payload** — the `context` validates against the action's contract (delegated to the target state).

**Reject is structured and side-effect-free** — every rejection kind is a refusal of consent (register A17, the `genesis_consent` framing): the router grants what the live tree affords and withholds what it does not. Four rejection kinds: `unknownComponent` (never existed in any emission), `staleUnmounted` (existed; the projection moved — **consent revoked because the world changed**), `undeclaredAction` (live component, action not in its catalog type), `badPayload` (declared action, invalid context). Every rejection path leaves the tree **byte-for-byte untouched — asserted, not assumed**: a canonical live-tree dump (config props AND live state) is captured before and after, plus zero builder invocations and an empty dirty set (spike 5 tests c, d, d2, e).

## Decision 3 — Staleness is a first-class rejection: the A8 bridge

The `staleUnmounted` case is where this ADR meets ADR-0001's "shed the original sin" decision (register A8). Spike 5 test e: a **v2 whole-tree re-emission through the same wire path** removes the target button; keyed reconcile unmounts exactly it while survivors keep element identity AND live counter state (the v2 reconcile itself runs zero builders). The previously-valid intent then rejects as `staleUnmounted` — distinguishable from `unknownComponent` because the surface keeps an ever-seen id set across emissions. *"The projection moved under the actor"* is a first-class, detectable outcome.

This is the agent-async-gap bug class, handled twice and at the right layers: genesis **sheds it at the type level** (`TreeContext` is a separate capability handle, never the `Branch` itself — A8, because agents routinely hold handles across async gaps) and **catches it at the protocol level** (the hit-test, because no type system stops a remote actor from acting on a projection it received two emissions ago). The structured rejection is exactly the feedback A8 needs to hand back to the agent.

## Decision 4 — Enforce applies through the target state; invalidation is exactly the target subtree

A valid intent is applied via the target state's `perceived()` (the `setState` analogue): the mutation is synchronous, and the rebuild flows through the standard pipeline — `markNeedsHarvest` → owner dirty set → `flushHarvest` (the spike's perception names for what is, in ADR-0001 vocabulary, the `TreeOwner` dirty/flush pipeline). **Exactly the target subtree rebuilds**: spike 5's builder-invocation counters prove the target button's builder ran again and the unrelated button's builder did NOT (test b), the harvest drains (a second flush is a no-op), and `onNeedsHarvest` wired to a `scheduleMicrotask` flush drains without any manual call (test b2). Enforcement is not a parallel mutation path — it is the same dirty/flush machinery every other invalidation uses, entered through a hit-tested gate.

## Decision 5 — Four audiences, one substrate; agent→machine is the tool-call projection

The four audiences — **human / agent / machine / self** — differ on exactly two things: *who supplies Intent* and *how Context renders* (the ADR-0001 rendering axis, with backends per ADR-0004). Nothing else forks. **Agent→machine is the tool-call projection**: the catalog-generated tool schema is Context rendered model-facing, the affordances within it are the `put` handles, and the A2UI `action` message is the Intent coming back.

**Vocabulary reconciliation (the_grid ADR-0002, "reactive domain projections"):** the grid projects typed, reactive views over beads — freezed value types plus named derived views encoding each mechanism's composition rule over the Beads Store. That is this same interfaces-as-projections concept at a different layer: grid projects a *domain* over a persistence substrate; genesis projects a *tree* over mounted live state. Same concept, different layer — the same disambiguation move as A4's two-reconcilers correction (grid's convergence state machine vs genesis's keyed tree diff). The collision is vocabulary, not duplication. Whether grid eventually mounts its bead domains as genesis `tree` nodes — inheriting keyed reconcile and this ADR's enforce/reject mechanism — is register **A7, which stays open**; this ADR does not resolve it.

## Decision 6 — Multi-party consensus stays parked; record the last-write-wins lean

What happens when two parties write the same projection is the genuinely novel surface, and it remains **deliberately unpromoted**. What this ADR records is the lean — **last-write-wins** — now backed by spike 5's probe (test f) instead of intuition:

- Writes apply **synchronously at route time, in arrival order**. Two `set` actions routed back-to-back both return `Applied` with honest change records (`0→5`, then `5→9`): the second write saw the first's result and overwrote it. Final state == last write; no merge, no conflict object, no rejection of the loser. A flush between the writes changes nothing (`3` then `7` → `7`). LWW falls out of "state is a single mutable cell + synchronous in-order application" — nothing had to be built to get it.
- The dirty set **coalesces** racing writes: two unflushed writes → ONE builder invocation showing only the final value. An observer of the rendered projection **never sees the intermediate write**; the `Applied{from,to}` change records are the only audit trail of the intermediate state.

The lean: LWW is the zero-mechanism default, and the `Applied`/`Rejected` results already carry from/to provenance. If consensus ever needs "every applied write is observable," LWW-with-coalescing is NOT that — observable-intermediate-states is a separate, explicitly-funded requirement if it ever appears. Spike 5's `timestamp` field is parsed leniently and unused in routing (ordering is purely arrival order); a real consensus story might use it — the probe deliberately did not. **Multi-party consensus beyond LWW is not decided here.**

---

## Decision 7 — The as-built `genesis_consent` surface; the action seam on the element; interop

*Added 2026-06-14 — promoted from register A28 (`genesis_consent` as-built, two-skeptic adversarial pass + tamper probes), A30 (the `@protected`-state / element-seam decision, decided by Nico), and A27 (the action-handling community-overlap finding). Decisions 1–6 set the mechanism; this records the shipped router and the ratified seam + interop calls.*

**The router (A28).** `ConsentRouter{surface, catalog}` is the front door for an action-enabled surface; it owns the emission ledger the hit-test needs — the ever-seen id set (`unknownComponent` vs `staleUnmounted`) and the current id → wire-type map (affordance lookup) — which `DialogueSurface` does not track, so emissions are driven through `router.mount`/`apply`. `route(ActionEvent)` runs the three gates of Decision 2 — exists/mounted (walk the live tree FRESH per call, no cached refs, A8), catalog-declared, payload — and returns a sealed `ConsentOutcome` = `Applied{action, componentId, ActionChange{from,to}}` | `Rejected{kind, message}`. `RejectionKind` is a flat enum of the four refusals; the outer outcome is the sealed union (exhaustive `switch`).

**Affordances are a runtime catalog lookup (A28, ratified).** The affordance gate reads `catalog.typeNamed(wireType).actions` from a parsed `Catalog` at runtime — the same `CatalogType.actions` the LLM saw projected as `x-actions` (one source of truth, ADR-0002). This is an as-built **divergence from this ADR's original mechanism text**, which referenced the spike's *generated* `componentActions`/`wireTypeOfPerception` map (`actions.g.dart`); `genesis_taxonomy` (A19) never carried that projection forward. A generated affordance map stays a possible future taxonomy optimization.

**The action seam is on the element, not via `.state` (A30, decided by Nico).** Enforcement reaches the target through `target is Actionable` on the live **branch** — the spike-5 "seam on elements." An actionable component implements `Actionable{validateAction (pure, gate 3) / applyAction (enforce via the state's setState-analogue)}` on its element (a `StatefulBranch`/`StatefulPerceptionElement` subclass that forwards to its own `State`). consent never reaches a branch's `State` directly: `StatefulBranch.state` is `@protected` (ADR-0001 Decision 3). `Actionable` lives in `genesis_consent`; `tree` stays artifact-agnostic — no action vocabulary in the spine. (This resolves the A28 "flagged wart," where consent reached the test-only `.state` getter.) Splitting pure `validateAction` from mutating `applyAction` is what makes a `badPayload` rejection byte-for-byte side-effect-free *by construction* (Decision 2).

**Developer errors throw; actor errors reject.** A `StateError` (not a `Rejected`) is raised when a catalog-declared action's component cannot honor it (no `Actionable`), or when a `sourceComponentId` resolves to **more than one** mounted branch — a DAG-shared id (built once per reference, ADR-0003 Decision 2 / A19): consent refuses to enforce against a duplicated id rather than mutate an arbitrary copy (A28, ratified — a surface must address each component by a unique id). The four-kind rejection taxonomy stays actor-feedback-only. Single-surface v1: a `surfaceId` mismatch folds into `unknownComponent`.

**Interop — the substrate is genesis-native (A27).** The STEP-1 community check (`docs/design/community-overlap-consent.md`) confirmed a2ui_core has **no action-enforcement model and no element tree to enforce against**: its `MessageProcessor` handles only server→client messages, client actions exit fire-and-forget via an `onAction` listener (no hit-test / affordance / rejection), and its component store never removes a component merely absent from the next emission — so `staleUnmounted` (Decision 3, the A8 bridge) is **not expressible** there. The enforce/reject substrate is genuinely ours; `genesis_consent` has **no a2ui_core dependency**. The only interop surface is the action *message vocabulary*, already aligned in `genesis_dialogue` (ADR-0003 Decision 5 / A25–A26: `ActionEvent` ↔ `A2uiClientAction`).

---

## Alternatives considered

- **Schema-only validation (no live tree)** — validate the action against the catalog and call it done. Rejected: it cannot detect staleness; only hit-testing the *live* tree fresh per route call makes "the projection moved under the actor" a detectable, distinguishable rejection (Decision 3). The catalog check is one gate of three, not the validator.
- **Cached element references in the router** — resolve the target once, hold the handle. Rejected: holding handles across async gaps is precisely the bug class A8 sheds; the router walks fresh on every call by design.
- **Boolean/silent rejection** — drop invalid actions or return `false`. Rejected: the structured four-kind taxonomy is the A8 feedback channel to the agent; `staleUnmounted` vs `unknownComponent` is the load-bearing distinction and a boolean erases it.
- **A separate enforcement mutation path** — apply valid actions by patching the tree directly. Rejected: applying through the target state's `perceived()` reuses the one dirty/flush pipeline, which is what makes "exactly the target subtree rebuilds" provable by counter (Decision 4).
- **Deciding consensus now (merge semantics, conflict objects, versioned writes)** — rejected as premature: the spike probe shows LWW is the zero-mechanism default with an honest audit trail; anything richer is speculative machinery with no funded requirement. Parked with a recorded lean instead (Decision 6).
- **Framework-supplied Intent** (autonomous framework behavior) — rejected: Intent is supplied by model/human/code, never the framework; that boundary is what keeps one substrate audience-neutral across all four audiences (Decisions 1, 5).

## Register provenance

This document promotes register entries from `docs/adr/ADR-0000-ai-decision-register.md`:

- **A5** — *The projection/manipulation substrate: four dynamics, four audiences, enforce/reject* → flip to `promoted → ADR-0005` on ratification.
- **A17** (folded 2026-06-13) — *Roadmap package names: `taxonomy` / `dialogue` / `consent`* — the action-router slot is named **`genesis_consent`**; the consume-relationships (`genesis_taxonomy`'s `x-actions` affordances in, intents out over the `genesis_dialogue` wire) are recorded in the Context amendment and Decisions 1–2. `genesis_consent` is **not yet built** — this records direction, not an as-built surface.

Promoted by the 2026-06-14 pass:

- **A28 (2026-06-14) — `genesis_consent` as-built enforce/reject surface** → Decision 7 (the router + three gates; runtime affordance lookup; the DAG-id `StateError`; the developer-error-vs-actor-feedback boundary; the single-surface fold).
- **A30 (2026-06-14) — `StatefulBranch.state` `@protected`; the action-dispatch seam on the element** → Decision 7 (the `target is Actionable` seam; `tree` stays action-free). *(A30's tree half is in ADR-0001 Decision 3.)*
- **A27 (2026-06-14) — the enforce/reject substrate is genesis-native; a2ui_core has no action-enforcement model** → Decision 7's interop paragraph.

Within A5, the multi-party-consensus question is **not** promoted — Decision 6 records the parked status and the LWW lean only; the consensus decision itself stays in the register until separately decided. Register **A7** (grid snapshot-diff vs genesis keyed reconcile, touched by Decision 5's vocabulary reconciliation) is **closed** (2026-06-14) as out-of-scope here — the_grid's adoption decision belongs in the_grid's own ADRs; the reconciler-vocabulary disambiguation already lives in ADR-0001 Decision 1 / ADR-0004 Decision 6.

Spike evidence cited throughout is untracked working-tree state under `com.nicospencer/lenny/spikes/` (`RESULTS.md`, `spike5_action_roundtrip/NOTES.md`); re-run commands are in the spike's `NOTES.md`.
