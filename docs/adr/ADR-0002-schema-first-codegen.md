# ADR-0002 — Schema-first codegen

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A2
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** the genesis node vocabulary — the catalog of node types `tree`/`perception` expose — has three simultaneous consumers: the Dart type system (typed construction), the LLM (the tool/JSON schema it authors A2UI surfaces against, ADR-0003 A2UI wire format), and the wire deserializer (ADR-0003's reconcile path). Register entry A2 (migrated from lenny's register when genesis was created) fixes the mechanism: the catalog is **schemas**; **codegen** emits everything else; `dart:mirrors` appears nowhere. This ADR transcribes A2 grounded in spikes 3 and 5 (two of the five green, adversarially verified de-risking spikes — lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`). **Evidence is working-tree-only:** spike artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md` + per-spike `NOTES.md`) and are disposable once genesis lands the real generator; paths and numbers are recorded here so the evidence stays auditable after the spike tree is gone.

---

## Decision 1 — One schema source generates both the Dart registry and the LLM tool schema

The catalog is a single schema document (spike 3: `spikes/spike3_schema_roundtrip/schema/catalog.json` — two types, `node` container and `field` leaf, with per-type/per-prop descriptions). One generator run emits two projections:

1. **`registry.g.dart` — the typed Dart factory registry** (`Map<String, Perception Function(props, children, key)>`), validating at construction time: unknown type, missing required prop, mistyped prop, unknown prop, and children-on-a-leaf all throw with diagnostics. Nothing outside the generated file hardcodes component type names — the wire deserializer goes exclusively through the generated `buildComponent(type, props, children, key)`.
2. **`tool_schema.g.json` — the LLM-facing JSON Schema** (draft 2020-12) for authoring an `updateComponents` message (A2UI v0.9, ADR-0003): the type enum via per-variant `component` const discriminators, the catalog's **descriptions flowing through** to every type and prop, `children` present for containers only and forbidden for leaves via `additionalProperties: false`.

**Affordances are catalog data and they reach the LLM.** Spike 5's catalog declares per-type `actions`; they project into the generated tool schema twice — structurally as an **`x-actions`** keyword on the button variant and as prose in the variant description ("AFFORDS CLIENT ACTIONS: … sourceComponentId … \"press\" …"). An LLM reading only the tool schema can discover which components afford which actions and how to address them (spike 5 test a); non-actionable types declare nothing. This is the origination point of ADR-0005's (Projection/action substrate) affordance channel: the same catalog line feeds the LLM's view and the hit-test gate.

**Byte-deterministic, tamper-tested.** The generator core is an importable pure function (`spikes/spike3_schema_roundtrip/lib/src/generator.dart`); the in-sync check regenerates in memory and asserts **byte-equality** with the files on disk. Falsified during the spike: appending a stray comment to `registry.g.dart` flipped the check red ("OUT OF SYNC … first diff at index 2319"); regenerating turned it green. Spike 5 carries the same check style across all three of its committed `.g` artifacts.

**Consequence:** the registry the runtime constructs from and the schema the LLM authors against cannot drift — both are byte-derived from one catalog, and the in-sync check is the standing guard.

## Decision 2 — No `dart:mirrors`; codegen is the one path uniform across VM, AOT, and web

`dart:mirrors` is unavailable under AOT compilation — which is to say under every Flutter release build — and is semi-abandoned upstream; Dart macros, the would-be in-language successor, were cancelled. A codegen'd registry is the only mechanism that runs identically on the bare VM, AOT, and web, and the only one that stays tree-shakeable (the registry is plain maps and constructor calls; unused vocabulary drops out at link time).

Spike 3 proves the uniformity by construction: no mirrors, no runtime reflection anywhere; the check functions are framework-free (`lib/checks.dart` throws `StateError`, imports no test framework), and the **identical five checks ran green under both `dart test` on the bare VM and `flutter test`** (`spikes/spike3_flutter_harness/`) — Dart 3.12.0, Flutter 3.44.0. One cross-binding gotcha is ledgered for the production generator: `Isolate.resolvePackageUriSync` throws `UnsupportedError` under flutter_test — resolve package roots by walking up to `.dart_tool/package_config.json` instead.

## Decision 3 — The generator is catalog- and package-generic (proven, not asserted)

Spike 5 reran spike 3's `generateFromCatalog` **unchanged** against a second catalog (panel/label/button) and produced a correct registry binding Dart classes from **three packages**: `Node` (package:perception), `Field` (spike 3's leaf, reused), and `CounterButton` (spike5-local `StatefulPerception`). Import parameterization — `package:` and relative — just worked. Cross-catalog, cross-package reuse with zero generator edits is itself the A2 evidence: the generator is generic over the vocabulary it is fed, which is the property Decision 6's extension composition stands on. Per ratified A11 (layering), `tree_codegen` is domain-neutral machinery: each domain owns its catalog, and perception's catalog never includes expression-row vocabulary.

## Decision 4 — Three seams the production generator MUST have

Spike 5's reuse run surfaced exactly three gaps (RESULTS.md findings ledger; `spikes/spike5_action_roundtrip/NOTES.md` "Generator-reuse feedback"). Each is a hard requirement on the production design:

1. **Catalog plugin keys.** The spike core silently ignores unknown type-level catalog keys — spike 5's `actions` declarations would have been **dropped** from the tool schema. The wrapper (`spikes/spike5_action_roundtrip/lib/src/generator.dart`) had to decode the generated JSON, inject `x-actions` + the description prose, re-encode, and emit a third projection (`actions.g.dart`) entirely outside the core. Silent dropping is the worst failure mode — the core throws loudly on unsupported *prop* shapes but not on unknown *type-level* keys. Production needs either first-class affordance declarations in the catalog format or a projection-plugin seam; unknown keys must be loud either way.
2. **Parameterized provenance headers.** Spike headers are hardcoded constants ("by tool/generate.dart (spike3)", title "updateComponents (spike3 catalog)"); spike 5's wrapper string-replaces them to keep committed artifacts honest. The generator takes a catalog/package identity parameter — the datum already exists in the catalog JSON (`"catalog": "spike5"`, currently unused).
3. **Tree-builder parameterized over the registry.** Spike 3's `buildPerceptionTree` hardcodes `import 'generated/registry.g.dart'` and the free function `buildComponent` — the **one minimal fork** spike 5 had to make (`lib/src/wire5.dart`, line-for-line re-bind to its own registry). Production: parameterize the builder over the component factory, or generate it per catalog next to the registry. (Envelope parsing — the spike's `SurfaceUpdate.fromJson`/`ComponentSpec` classes; the Dart class keeps a v0.8-era name but parses the v0.9 `updateComponents` wire shape, per spike 3's ledger — reused unchanged; the fork is exactly one seam wide.)

## Decision 5 — Production shape: a build_runner builder, per the house conventions

Per the A6 conventions (promoted via ADR-0001 Foundations), the production generator is a **build_runner builder** wired into melos. **Recorded divergence:** both spikes generated via a plain `dart run tool/generate.dart` script — a deliberate spike shortcut. The move is pre-paid: the core is already factored as the pure importable `generateFromCatalog`, so the builder is a wrapper, not a rewrite. The byte-equality in-sync check (Decision 1) carries over as the CI guard on committed `.g` artifacts.

Two further spike shortcuts are explicitly **not** carried forward and remain open design work for the production generator (flagged for ratification, undecided here): the spike generator supports only `string`-typed required props (throwing loudly on anything else), and the generated registry throws bare `StateError`s where the agent loop wants a structured error type it can feed back to the LLM.

## Decision 6 — Extension vocabularies join the core registry through lenny's extension contract

The codegen'd core registry is not the whole vocabulary. Per lenny register A1 (`com.nicospencer/lenny/docs/adrs/0000-ai-decision-register.md`), registration must compose with lenny's **extension contract** — the pure-Dart **`exploration_contract`** package (`plugin.dart` / `types.dart` / `registry.dart` / `plugin_context.dart`) — the seam by which extensions contribute their own node vocabularies, schemas, and `ext.exploration.*` surfaces. Decisions 3 and 4 are what make that composition mechanical rather than aspirational: an extension ships a catalog; the same generator (catalog-generic, provenance-parameterized, registry-parameterized) emits its registry and tool-schema fragment; registration merges them into the core through `exploration_contract`'s `registry.dart`. Retrieval/search over a large multi-extension catalog stays **parked** per lenny A1 — eat the context now, optimize later.

Boundary note: lenny A1 is pending in *lenny's* register and ratifies there; this ADR records only the genesis-side requirement that the registry expose the composition seam.

---

## Alternatives considered

- **`dart:mirrors` registry** — rejected: unavailable under AOT/Flutter, semi-abandoned upstream, defeats tree-shaking; would fork the implementation by target, which is the exact non-uniformity A2 exists to avoid.
- **Wait for Dart macros** — not available to wait for: cancelled. There is no in-language metaprogramming path.
- **Two hand-maintained sources** (registry written by hand, tool schema written by hand) — rejected: drift between what the LLM is told it can author and what construction accepts is precisely the bug class one-source-codegen kills, and the byte-determinism check (Decision 1) is only possible with a single source.
- **Runtime catalog interpretation** (ship `catalog.json`, build factories dynamically) — rejected: loses construction-time typed validation and tree-shaking; the vocabulary would be stringly-typed at runtime on every target.
- **Keep the script generator in production** — rejected per the A6 conventions (ADR-0001 Foundations); the spike's script form is recorded as a divergence in Decision 5, with the core already factored for the build_runner move.

---

## Register provenance

This document promotes **exactly one** entry from `genesis/docs/adr/ADR-0000-ai-decision-register.md`; on ratification, Nico flips its status:

| Entry | Title | Status flip on ratification |
|---|---|---|
| **A2** (2026-06-11) | Node vocabulary is schema-first + codegen; `dart:mirrors` dropped *(migrated from lenny A1)* | pending → promoted → ADR-0002 |

Cited but **not** promoted here: genesis **A6** (house conventions — promotes via ADR-0001 Foundations), genesis **A3** (wire grammar — ADR-0003 A2UI wire format), genesis **A5** (affordances/enforce-reject — ADR-0005 Projection/action substrate), and **lenny register A1** (extension-contract composition — lives in lenny's register and is ratified there, not here). Genesis **A7** is untouched and stays open.

Evidence provenance: all spike citations refer to **untracked working-tree state** under `com.nicospencer/lenny/spikes/` (spike 3: `spike3_schema_roundtrip/` + `spike3_flutter_harness/`; spike 5: `spike5_action_roundtrip/`; verdicts in `RESULTS.md`). Re-run commands are in each spike's `NOTES.md`. Verify before the spike tree is cleaned up.
