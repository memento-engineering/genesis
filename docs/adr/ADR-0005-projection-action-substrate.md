# ADR-0005 — Projection/action substrate: four dynamics, four audiences, enforce/reject

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A5 (multi-party consensus explicitly NOT promoted — parked, lean last-write-wins)
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** ADR-0001 (Foundations) fixes the engine (`Seed`/`Branch`/`TreeContext`/`TreeOwner`) and the two-axis model; ADR-0002 (Schema-first codegen) fixes how the node catalog becomes both a Dart registry and an LLM tool schema; ADR-0003 (A2UI wire format) fixes the bidirectional grammar; ADR-0004 (Render backends) fixes how one tree renders to many audiences. This ADR names the *manipulation* half: what it means for any party — model, human, or code — to act on a projected tree, and what the framework does when the act is valid or invalid. It promotes register entry A5 and unparks the half lenny ADR 0001 explicitly parked ("Decisions & forks" §3, the action/affordance half — `com.nicospencer/lenny/docs/adrs/0001-declarative-perception-framework.md`). Every claim below is grounded in spike 5 (`spike5_action_roundtrip`, bead `lenny-78r1`): 9 tests green on the bare VM (`dart test`, Dart 3.12.0), adversarially verified. **Evidence is working-tree-only:** the spike artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md` + `spike5_action_roundtrip/NOTES.md`) per the spike-first constraint — disposable reference evidence once genesis lands the real thing.

---

## Decision 1 — Interfaces are projections; four dynamics, bound to the tree vocabulary

Frame the whole system as **interfaces-as-projections**: a `get` projection plus `put` handles. Four dynamics, each bound to a concrete mechanism already in the tree vocabulary — none of them new machinery:

| Dynamic | Is | Mechanism |
|---|---|---|
| **Context** | the projection itself | the mounted tree, rendered per the ADR-0001 rendering axis (serialize / typed structs / render tree — ADR-0004) |
| **Attention** | what the projection tracks | the subscription graph (`Watch`) — plus the focus-policy knob (lenny ADR 0001's ambient `PerceptionPolicy`), which **stays parked**; only the binding is promoted here. Per register A13 (pending), `Watch` is slated for `tree`'s composition layer — the Attention primitive is substrate-level — with `perception` re-exporting it. |
| **Affordance** | what the projection can be asked to do | **catalog-declared actions** — and as of spike 5 they are *executable*, not aspirational: the catalog's per-type `actions` map flows into the generated tool schema (an `x-actions` keyword on the button variant plus prose in the variant description), so an LLM reading only the tool schema discovers which components afford which actions and how to address them (`sourceComponentId`, `"press"`). Non-actionable types (label, panel) declare nothing. One catalog is simultaneously the affordance declaration the LLM sees and the affordance check the router enforces (`componentActions` + `wireTypeOfPerception` in the generated `actions.g.dart`) — the ADR-0002 one-schema property, extended to actions. |
| **Intent** | the thing the framework does **not** supply | brought by the actor — model, human, or code. The framework projects and enforces; it never wants. |

This names what lenny ADR 0001 §3 half-formalized and parked ("dynamic, state-derived tool lists harvested from the tree"), and generalizes single-app-observe into a multi-party substrate.

## Decision 2 — Validation/invalidation = enforce/reject; action validation IS hit-testing

An incoming intent (A2UI v0.9 `action` message: `{name, surfaceId, sourceComponentId, timestamp, context}`) is validated by **hit-testing the live mounted tree** — lenny ADR 0001's "action validation == hit-testing" line, now executable. Spike 5's router (`spike5_action_roundtrip/lib/action_router.dart`) gates in three catalog/tree-derived steps, none hardcoded:

1. **exists/mounted** — `sourceComponentId` resolves to a MOUNTED element by walking the live tree *fresh on every route call* (no cached element refs);
2. **catalog-declared** — the live element's catalog type declares the action name, looked up in generated catalog-derived data, so the affordance check and the LLM-visible affordance declaration share one source of truth;
3. **payload** — the `context` validates against the action's contract (delegated to the target state).

**Reject is structured and side-effect-free.** Four rejection kinds: `unknownComponent` (never existed in any emission), `staleUnmounted` (existed; the projection moved), `undeclaredAction` (live component, action not in its catalog type), `badPayload` (declared action, invalid context). Every rejection path leaves the tree **byte-for-byte untouched — asserted, not assumed**: a canonical live-tree dump (config props AND live state) is captured before and after, plus zero builder invocations and an empty dirty set (spike 5 tests c, d, d2, e).

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

## Alternatives considered

- **Schema-only validation (no live tree)** — validate the action against the catalog and call it done. Rejected: it cannot detect staleness; only hit-testing the *live* tree fresh per route call makes "the projection moved under the actor" a detectable, distinguishable rejection (Decision 3). The catalog check is one gate of three, not the validator.
- **Cached element references in the router** — resolve the target once, hold the handle. Rejected: holding handles across async gaps is precisely the bug class A8 sheds; the router walks fresh on every call by design.
- **Boolean/silent rejection** — drop invalid actions or return `false`. Rejected: the structured four-kind taxonomy is the A8 feedback channel to the agent; `staleUnmounted` vs `unknownComponent` is the load-bearing distinction and a boolean erases it.
- **A separate enforcement mutation path** — apply valid actions by patching the tree directly. Rejected: applying through the target state's `perceived()` reuses the one dirty/flush pipeline, which is what makes "exactly the target subtree rebuilds" provable by counter (Decision 4).
- **Deciding consensus now (merge semantics, conflict objects, versioned writes)** — rejected as premature: the spike probe shows LWW is the zero-mechanism default with an honest audit trail; anything richer is speculative machinery with no funded requirement. Parked with a recorded lean instead (Decision 6).
- **Framework-supplied Intent** (autonomous framework behavior) — rejected: Intent is supplied by model/human/code, never the framework; that boundary is what keeps one substrate audience-neutral across all four audiences (Decisions 1, 5).

## Register provenance

This document promotes exactly one register entry from `docs/adr/ADR-0000-ai-decision-register.md`:

- **A5** — *The projection/manipulation substrate: four dynamics, four audiences, enforce/reject* → flip to `promoted → ADR-0005` on ratification.

Within A5, the multi-party-consensus question is **not** promoted — Decision 6 records the parked status and the LWW lean only; the consensus decision itself stays in the register until separately decided. Register **A7** (grid snapshot-diff vs genesis keyed reconcile, touched by Decision 5's vocabulary reconciliation) **stays open** — referenced, not promoted.

Spike evidence cited throughout is untracked working-tree state under `com.nicospencer/lenny/spikes/` (`RESULTS.md`, `spike5_action_roundtrip/NOTES.md`); re-run commands are in the spike's `NOTES.md`.
