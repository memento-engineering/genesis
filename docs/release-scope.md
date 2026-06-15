# Release scope — what's in 1.0, what's deferred

**Date:** 2026-06-14 · Honest ledger of the 1.0 boundary, so the deferred
surface is visible rather than hidden. The `taxonomy → dialogue → consent` arc
plus the `tree`/`perception`/`typesetting` substrate is built and tested; this
records what ships and what is explicitly *not yet*.

## In scope (built, tested, shipping)

| Area | Surface |
|---|---|
| Engine (`tree`) | `Seed`/`Branch`/`TreeContext`/`TreeOwner`, keyed reconcile, the A18 identical-skip fast path, the composition layer (`Stateless`/`Stateful`/`State`, `InheritedSeed`, `Watch`, `Sprout`) — composition layer **EXPERIMENTAL** (may change pre-1.0) |
| Measurement (`perception`) | `Perception`/`PerceptionContext`/`PerceptionOwner`, `Node`/`Field`, the harvest pipeline |
| Codegen (`taxonomy`) | catalog → factory registry + LLM tool schema (one source of truth), the extension seam, structured errors, build_runner integration |
| Wire (`dialogue`) | A2UI v0.9 `updateComponents` codec, the receive-side `DialogueSurface` (reconcile re-emissions by key), `action`-message parsing |
| Render (`typesetting`) | bare-VM cell/ANSI render-branch backend (`Stage`/`Box`/`Text`), double-buffered diff emission |
| Action substrate (`consent`) | enforce/reject hit-test against the live tree + catalog affordances, the four-kind rejection taxonomy, enforce via the target state |

## Deferred — post-1.0 (intentionally not built)

| Deferred | Why / where it goes |
|---|---|
| **`dialogue` reverse-emission** (live tree → `updateComponents`) | needs a `taxonomy` reverse-describer that doesn't exist; the receive + re-emit-by-key path is what 1.0 needs (A25) |
| **`updateDataModel` / data binding** | A2UI's JSON-Pointer data model + expression evaluation; the natural home is adopting `a2ui_core`'s `DataModel` post-stable (A26) |
| **`createSurface` / `deleteSurface` lifecycle, streaming** | single-surface, whole-message v1 is enough for 1.0 (A25) |
| **`genesis_expression`** (Flutter design system / windowed backend) | not a 1.0 ship target; the `expression` branch is a standalone Flutter design language that does not yet consume the genesis spine — reconciling it with a genesis-tree Flutter render backend is post-1.0 (A29 context) |
| **The agent loop** | the model↔genesis driver (author → receive → render → enforce); will adopt `genai_primitives` for the chat/tool vocabulary rather than invent it (A26 item 4) |
| **`tree` first-class action-dispatch hook** | `consent` reaches the target state via `StatefulBranch.state` (a flagged known wart that works); a blessed branch-level dispatch seam is the proper successor (A28 flag 1 / A29 — `Sprout`'s `useAction` could subsume it) |
| **`tree` optimization** | inherited-lookup cache (O(depth)→O(1)) + lazy `_dependencies`; measure-gated, not a release blocker |
| **`taxonomy` generated affordance map** | `consent` reads affordances from a runtime `Catalog.parse(...)` lookup; a generated `componentActions` projection is an optional optimization (A28 flag 3) |
| **`Sprout` extras** | `useReducer`, a synchronous `useLayoutEffect`, a `PerceptionSprout` domain face — deferred until a real second consumer (A29) |

## Known interop posture (A26)

genesis interoperates with `flutter/genui`'s A2UI stack rather than forking it:
the wire vocabulary is aligned (`dialogue.ActionEvent` ↔ `a2ui_core`'s
`A2uiClientAction`; the `updateComponents` envelope), proven by a conformance
test that depends on no genui package. `a2ui_core` (≥ 1.0) is the intended
message-model dependency post-stable; `genai_primitives` is the intended
agent-loop vocabulary; `json_schema_builder` is an optional schema-emit swap.

## Before publishing to pub.dev

1. ~~**Promote** the pending register entries into their ADRs.~~ **Done
   (2026-06-14)** — A25–A31 promoted; A7 closed; register is clean.
2. ~~**Flip dependencies** + drop `publish_to: none`.~~ **Done (2026-06-14,
   A32)** — inter-package deps pinned to hosted `^0.1.0`; `publish_to: none`
   dropped from the six members (the root workspace pubspec keeps it).
   `dart pub publish --dry-run` on `genesis_tree` validates; `resolution:
   workspace` stays for local dev resolution.
3. ~~Per-package `README.md` + `CHANGELOG.md` (the dry-run's standing
   warnings).~~ **Done (2026-06-14)** — added READMEs for `tree` / `perception`
   (the other four already had them) and an initial `0.1.0` `CHANGELOG.md` for
   all six; `dart pub publish --dry-run` on `genesis_tree` is now clean.
4. ~~**Refine the public docs** — strip internal references from everything
   pub.dev renders.~~ **Done (2026-06-14)** — descriptions (commit `863380b`)
   plus all six **READMEs**, every **lib docblock**, and the **CHANGELOGs**
   scrubbed of inline ADR/register numbers, spike/`NOTES.md` references,
   `docs/adr/` / "monorepo" pointers, and the unshipped `genesis_expression`
   mention; load-bearing refs rewritten as plain prose. Two user-facing
   error-strings (`tree_context.dart`, `consent/router.dart`) also de-jargoned.
   Decision: **self-contained, no design pointers** — pub.dev already links the
   repo from each pubspec's `repository:` field, so the prose carries none.
   Verified clean (internal-ref + bare-`A<n>` greps empty bar legitimate
   domain text); `dart format` 0-changed, `dart analyze` clean, full `melos run
   test` green.
5. **Publish — via `melos publish`** (the remaining outward step). `melos
   publish` is dry-run by default and resolves the dependency order
   automatically; `melos publish --no-dry-run` does the real publish. Order:
   `genesis_tree` → `genesis_perception` + `genesis_taxonomy` →
   `genesis_typesetting` + `genesis_dialogue` → `genesis_consent` (each
   package's `^0.1.0` deps must already be on pub.dev). Needs pub.dev auth, so
   it's a human run. Future version bumps + changelogs: `melos version`
   (Conventional Commits) once there are release tags.
6. **Assign each package to the `memento.engineering` verified publisher.** pub
   has no publisher pubspec field or CLI flag — packages publish under the
   uploader's Google account first, then transfer via the web UI: each
   package's page → **Admin** → enter `memento.engineering` →
   **Transfer to Publisher**. Once per package, and **irreversible** (can't move
   back to an individual). After transfer, any publisher member can publish
   future versions. (No repo change — package names stay `genesis_*`; the
   publisher is the verified owner identity, not a name prefix.)
