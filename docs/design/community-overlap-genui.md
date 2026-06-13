# Community overlap: flutter/genui's A2UI stack vs. genesis

**Date:** 2026-06-13 · **Status:** findings + recommendation (register A26, pending Nico)

Assessment of whether genesis duplicated functionality already shipping in the
`flutter/genui` monorepo, and whether we should pull our code back and
interoperate. Triggered by Nico pointing at `a2ui_core`, `json_schema_builder`,
and `genai_primitives`.

## The deciding fact

**All three lower-layer genui packages are pure Dart, bare-VM-safe, BSD-3,
published by `labs.flutter.dev`.** The Flutter/`dart:ui` coupling is quarantined
entirely in the top-level `genui` renderer (0.9.2, `flutter: sdk: flutter`) —
the exact layer `genesis_typesetting` / `genesis_expression` replace. So our
bare-VM purity guard does **not** rule any of them out; the only real blocker to
adoption is maturity.

## The genui architecture (as found)

```
json_schema_builder  (schema build + validate, draft 2020-12)
        │
        ├── a2ui_core        (A2UI v0.9 protocol model + reactive DataModel)   ── parallel ──   genai_primitives (chat/parts/tool vocabulary)
        │                                                                                              │
        └────────────────────────── genui (Flutter renderer, the ONLY Flutter-coupled package) ───────┘
                                     genui_a2a (transport adapter)
```

`a2ui_core` and `genai_primitives` are two parallel pure-Dart foundations;
`a2ui_core` does **not** depend on `genai_primitives`.

## Package facts

| Package | pub | Publisher | License | Maturity | VM-safe? |
|---|---|---|---|---|---|
| `a2ui_core` | `0.0.1-dev002` (`-wip` at HEAD) | labs.flutter.dev | BSD-3 | **Very early** — 1 like, stub README, unstable API; deps `preact_signals` + `json_schema_builder` | **Yes** (only Flutter refs are non-runtime `@docImport`) |
| `json_schema_builder` | `0.1.5` | labs.flutter.dev | BSD-3 | **Most mature** — 27 likes, ~49k downloads, active | **Yes** (conditional import lands on `dart:io` on the VM) |
| `genai_primitives` | `0.2.3` (`0.2.4-wip` HEAD) | labs.flutter.dev | BSD-3 | Pre-1.0, `-wip` | **Yes** (`cross_file`'s `fromFile` touches platform APIs; the core types don't) |

## Overlap matrix

| Our package | Community | Verdict |
|---|---|---|
| `genesis_dialogue` | **`a2ui_core`** | **Real overlap.** Both pure-Dart A2UI **v0.9**, same string `component` discriminator, flat components, parse/serialize `updateComponents` + client actions. We rebuilt the codec. |
| `genesis_taxonomy` | `json_schema_builder` | **Mostly orthogonal.** Our catalog→factory-registry **codegen** has no counterpart (json_schema_builder is runtime build+validate, no codegen). Only our schema-emission + validation overlaps (we already dev-dep `json_schema` there). |
| — *(gap)* | **`genai_primitives`** | **Not duplicated — a gap.** It's the LLM conversation/tool vocabulary (`ChatMessage`, `Part`/`StandardPart`, `ToolDefinition`). We'll need it for the agent loop and don't have it. |
| `genesis_tree` / `perception` / `typesetting` | **none** | **The bet, unduplicated.** genui is Flutter/Skia; nobody ships an extracted Seed/Branch engine, a measurement domain, or a bare-VM ANSI renderer. |

We duplicated **one layer** — the A2UI wire codec — not the substrate.

## `a2ui_core` nuance

It is the canonical v0.9 protocol model from Google labs, and **more complete
than our `dialogue` v1**: it has `createSurface`/`deleteSurface` lifecycle and
`updateDataModel` data binding (both deferred in dialogue), plus a reactive
`DataModel` (JSON-Pointer store) and an expression evaluator. But: it's
`0.0.1-wip`, drags in `preact_signals` + the heavier catalog/data-model/binder
stack, keeps components as raw `List<Map>`, and is **surface-id-centric** with no
`id=="root"` convention found — where our wire is lean (`id=="root"`, no surface
envelope, no `rootId`). It has **no rendering substrate** (its "binder" resolves
prop bindings to reactive values, not widgets).

## Recommendation — interoperate, don't pull back

The substrate is the moat and it's unduplicated; the value of a standard is
interop, so a private dialect of A2UI is worth nothing.

1. **Now (cheap, low-risk):** treat `a2ui_core` as the **conformance oracle +
   interop target** — a round-trip/adapter test asserting our `updateComponents`
   envelope is compatible with `a2ui_core`'s `UpdateComponentsMessage`. Catches
   the `id=="root"` vs surface-envelope drift; proves an `a2ui_core`-producing
   agent can drive a genesis surface. **No dependency on a wip package.**
2. **Post-stable (a2ui_core ≥ 1.0):** collapse `genesis_dialogue` to the
   *reconcile-onto-tree adapter* and depend on `a2ui_core` for the message model
   — inheriting its `createSurface` lifecycle + `updateDataModel` data binding we
   deferred, and riding its v0.9 conformance instead of forking it.
3. **`json_schema_builder`:** optional, modest — swap our hand-assembled schema
   map + `json_schema` dev-dep for the lib the rest of the ecosystem uses. Our
   codegen stays ours.
4. **`genai_primitives`:** when the model↔genesis agent loop is built, **adopt
   this, don't invent** `ChatMessage`/`Part`/`ToolDefinition`.
5. **Reposition:** genesis is *the framework-agnostic renderer + substrate for
   the A2UI ecosystem*. `genesis_typesetting` is a bare-VM A2UI renderer genui
   (Flutter-only) structurally cannot offer — a contribution angle, not a
   competition.

**Do NOT depend on `a2ui_core` today** — `0.0.1-wip` + 1 like + `preact_signals`
is too much instability under a core layer.

## Sources

a2ui_core / json_schema_builder / genai_primitives pubspecs + lib + READMEs
(raw.githubusercontent.com/flutter/genui), pub.dev pages, GitHub contents API
(`flutter/genui/packages`). Researched 2026-06-13.
