# genesis_consent — handoff (2026-06-13)

One-file pickup for a fresh **genesis-rooted** session to build `genesis_consent`
(bead `genesis-hjj`) — the enforce/reject action router (ADR-0005). This
conversation built `tree`/`perception`/`taxonomy`/`typesetting`/`dialogue` and
ratified the register through A26; consent is the last package on the original
`taxonomy → dialogue → consent` arc.

## First, orient (read these)
- `docs/adr/ADR-0000-ai-decision-register.md` — the decision register (the **Rule**: AI records decisions as `A<n>` amendments, only Nico promotes). Relevant entries: **A5** (projection/action substrate — enforce/reject = hit-testing), **A17** (the `genesis_consent` name), **A19** (taxonomy's catalog-declared `x-actions` affordances + `CatalogExtension`), **A25** (dialogue's `ActionEvent`, parse-only), **A26** (the interoperate-don't-fork principle).
- `docs/adr/ADR-0005-projection-action-substrate.md` — the ratified spec for this package.
- `docs/design/community-overlap-genui.md` — the genui/A2UI overlap findings.
- `docs/evidence/spikes-2026-06-11/spike5_action_roundtrip-NOTES.md` — the spike-5 reference implementation (the enforce/reject mechanism, proven).
- `CLAUDE.md` — conventions (A6 house style; A21 "extension" never "plugin"; A22 tests consume `genesis_perception`).

## STEP 1 (do this BEFORE building) — the consent community check
`genesis_consent` is the **highest community-overlap-risk** package of the set;
the genui research so far covered the wire/schema/primitives, NOT the
action-handling/enforcement model. Per **A26** (interoperate, don't fork), run a
focused overlap check before writing the router:
- **`a2ui_core`** (flutter/genui): how does it handle the **client→server action message** (`A2uiClientAction`) and its `MessageProcessor` + reactive `DataModel` (JSON-Pointer updates + expression evaluator)? Does it already apply action *effects* in a way we should adopt or interop with?
- **`genai_primitives`**: is `ToolDefinition` the right vocabulary for affordance declaration?
- Record the finding as a register amendment + a `docs/design/community-overlap-consent.md` note (mirror `community-overlap-genui.md`), then build.

## Expected adopt/keep split (prior — verify in STEP 1)
Same shape that protected `dialogue` (codec interop'd; reconcile-onto-tree was ours):
- **Interop / adopt:** the action *message vocabulary* — align dialogue's `ActionEvent` with a2ui_core's `A2uiClientAction`; possibly `genai_primitives.ToolDefinition` for affordances.
- **Genesis-native (the moat):** the **enforce/reject hit-test against the live `Seed`/`Branch` tree + taxonomy's catalog-declared `x-actions` affordances**; the rejection taxonomy (unknownComponent / staleUnmounted / undeclaredAction / badPayload) leaving the tree byte-for-byte untouched; `staleUnmounted` = consent revoked because the world changed (the A8 async-gap bridge); enforce via the target state's `perceived()`. a2ui_core has **no element-tree substrate to hit-test against**, so this layer is genuinely ours.
- **Parked:** multi-party consensus — lean last-write-wins (A5; the spike-5 probe is the evidence).

## What consent consumes (the seams that already exist)
- `genesis_dialogue` — `parseActionEvent → ActionEvent{name, surfaceId, sourceComponentId, payload, timestamp?}` (parse-only; routing was explicitly left to consent) + the live `DialogueSurface` (mounted tree + owner to hit-test against).
- `genesis_taxonomy` — the `CatalogExtension` `actions` seam → `CatalogType.actions` + the generated `x-actions` tool-schema (the affordance declarations to hit-test against).
- `genesis_tree` / `genesis_perception` — the live mounted tree; enforce mutates via `perceived()` (the A18 fast path is in: identical-skip on reconcile).

## Build discipline (how this conversation worked)
- Spike-first proved the mechanism (spike 5); productionize against the as-built packages.
- Build → adversarial verify (repro + design/fidelity skeptics, tamper probes) → land; gate on the consuming packages staying green.
- Record as-built API decisions as a pending register entry (the `A<n>` after A26); the keeper (Nico) promotes. Pure-Dart, bare-VM; no "plugin" wording; tests use perception's `Node`/`Field`.
- Land direct-to-main with logical commits; `Co-Authored-By` trailer; push.

## Recall prompt (paste to start)
> Read `docs/genesis-consent-handoff.md` and the docs it links. Do STEP 1 (the consent community check vs a2ui_core action-handling + genai_primitives) and record it, THEN build `genesis_consent` (bead `genesis-hjj`): the genesis-native enforce/reject hit-test against the live tree + taxonomy affordances, consuming dialogue's `ActionEvent`. Build → adversarially verify → land; record the as-built surface as a pending register entry.
