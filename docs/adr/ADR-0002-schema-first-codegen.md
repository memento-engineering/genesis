# ADR-0002 — Schema-first codegen

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A2
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** the genesis node vocabulary — the catalog of node types `tree`/`perception` expose — has three simultaneous consumers: the Dart type system (typed construction), the LLM (the tool/JSON schema it authors A2UI surfaces against, ADR-0003 A2UI wire format), and the wire deserializer (ADR-0003's reconcile path). Register entry A2 (migrated from lenny's register when genesis was created) fixes the mechanism: the catalog is **schemas**; **codegen** emits everything else; `dart:mirrors` appears nowhere. This ADR transcribes A2 grounded in spikes 3 and 5 (two of the five green, adversarially verified de-risking spikes — lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`). **Evidence is working-tree-only:** spike artifacts live untracked at `com.nicospencer/lenny/spikes/` (`RESULTS.md` + per-spike `NOTES.md`) and are disposable once genesis lands the real generator; paths and numbers are recorded here so the evidence stays auditable after the spike tree is gone.

*Amended 2026-06-13 — promoted from register A17 (codegen package is named **`genesis_taxonomy`**, replacing the `tree_codegen` working name), A21 ("extension", never "plugin" — the seam is `CatalogExtension`; all "plugin" wording swept), and A19 (the `genesis_taxonomy` as-built surface — folded into Decision 4 and the new Decision 7). Working name `tree_codegen` reads `genesis_taxonomy` throughout below.*

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

Spike 5 reran spike 3's `generateFromCatalog` **unchanged** against a second catalog (panel/label/button) and produced a correct registry binding Dart classes from **three packages**: `Node` (package:perception), `Field` (spike 3's leaf, reused), and `CounterButton` (spike5-local `StatefulPerception`). Import parameterization — `package:` and relative — just worked. Cross-catalog, cross-package reuse with zero generator edits is itself the A2 evidence: the generator is generic over the vocabulary it is fed, which is the property Decision 6's extension composition stands on. Per ratified A11 (layering), `genesis_taxonomy` is domain-neutral machinery: each domain owns its catalog, and perception's catalog never includes expression-row vocabulary.

## Decision 4 — Three seams the production generator MUST have

Spike 5's reuse run surfaced exactly three gaps (RESULTS.md findings ledger; `spikes/spike5_action_roundtrip/NOTES.md` "Generator-reuse feedback"). Each is a hard requirement on the production design.

*Amended 2026-06-13 — promoted from register A19 (the `genesis_taxonomy` as-built surface, commit `2e8aaa2`, 73/73 tests, adversarially verified incl. seam tampers) and A21 (the seam word is **extension**, never "plugin"). The three seams below were built; their as-built shape is recorded inline.*

1. **The `CatalogExtension` seam (was "catalog plugin keys").** The spike core silently ignores unknown type-level catalog keys — spike 5's `actions` declarations would have been **dropped** from the tool schema. The wrapper (`spikes/spike5_action_roundtrip/lib/src/generator.dart`) had to decode the generated JSON, inject `x-actions` + the description prose, re-encode, and emit a third projection (`actions.g.dart`) entirely outside the core. Silent dropping is the worst failure mode — the core throws loudly on unsupported *prop* shapes but not on unknown *type-level* keys. Unknown keys must be loud either way.
   **As built (A19):** the core format owns exactly the type-level keys `description` / `container` / `props` / `dart`; **every other type-level key is extension vocabulary**, and any unclaimed key across the whole catalog throws once as `UnhandledCatalogKeysException` (loud, listing the keys and the registered extensions). The seam is the `CatalogExtension{name, typeKeys, parseTypeValue, augmentToolSchemaVariant}` interface: an extension claims type-level keys via `typeKeys`, parses each claimed key's raw value through `parseTypeValue` (landing in `CatalogType.extensions`), and projects into the LLM-facing schema variant via `augmentToolSchemaVariant`. **Actions ride this seam as the proof** — the `actions` block is itself extension vocabulary, not a core key: `ActionsCatalogExtension` (shipped in `defaultCatalogExtensions`) parses it into `ActionDeclaration` data on `CatalogType.actions` and projects it as `x-actions` + description prose into the tool schema; `genesis_consent` (ADR-0005) consumes the affordance data later.
2. **Parameterized provenance headers (seam 2).** Spike headers are hardcoded constants ("by tool/generate.dart (spike3)", title "updateComponents (spike3 catalog)"); spike 5's wrapper string-replaces them to keep committed artifacts honest. The generator takes a catalog/package identity parameter — the datum already exists in the catalog JSON (`"catalog": "spike5"`, currently unused).
   **As built (A19):** provenance is fully parameterized from the catalog `catalog` name block; generated Dart is post-formatted via `dart_style` (passes the repo format gate); both the registry and tool-schema emitters are byte-deterministic.
3. **Tree-builder parameterized over the registry (seam 3).** Spike 3's `buildPerceptionTree` hardcodes `import 'generated/registry.g.dart'` and the free function `buildComponent` — the **one minimal fork** spike 5 had to make (`lib/src/wire5.dart`, line-for-line re-bind to its own registry). Production: parameterize the builder over the component factory, or generate it per catalog next to the registry. (Envelope parsing — the spike's `SurfaceUpdate.fromJson`/`ComponentSpec` classes; the Dart class keeps a v0.8-era name but parses the v0.9 `updateComponents` wire shape, per spike 3's ledger — reused unchanged; the fork is exactly one seam wide.)
   **As built (A19):** the `ComponentRegistry` runtime lives in the library; generated files are thin wiring (a `componentRegistry` instance per catalog). `buildSeedTree(registry, components, {rootId})` takes the registry **as a parameter, never an import** — component id becomes the `Seed` key; cycles are rejected with the id path; a DAG shares-build twice (spike behavior kept).

## Decision 5 — Production shape: a build_runner builder, per the house conventions

Per the A6 conventions (promoted via ADR-0001 Foundations), the production generator is a **build_runner builder** wired into melos. **Recorded divergence:** both spikes generated via a plain `dart run tool/generate.dart` script — a deliberate spike shortcut. The move is pre-paid: the core is already factored as the pure importable `generateFromCatalog`, so the builder is a wrapper, not a rewrite. The byte-equality in-sync check (Decision 1) carries over as the CI guard on committed `.g` artifacts.

**As built (A19, amended 2026-06-13):** the production builder maps `*.catalog.json` → sibling `.g.dart` + `.g.json`, `build_to: source`, with an in-sync test as the standing guard. The shipped builder runs `defaultCatalogExtensions` only; a domain needing custom extensions wraps `generateFromCatalog(json, extensions: [...])` in its own builder.

Two further spike shortcuts were flagged here as open design work. *Both are now resolved (A19, amended 2026-06-13):*
- **Prop typing.** The spike generator supported only `string`-typed required props (throwing loudly on anything else). As built, props are fully typed — `string` / `integer` / `number` / `boolean` / `enum(values)` — with `required` stated explicitly and **optional props that MUST declare a `default`** (both directions enforced at parse; a default whose type or enum membership doesn't match is rejected; explicit JSON `null` is treated as absent).
- **Structured errors.** The spike registry threw bare `StateError`s where the agent loop wants a structured error type it can feed back to the LLM. As built, a **sealed `TaxonomyException` hierarchy** replaces them — three families for exhaustive switching (`CatalogException`, `ComponentBuildException`, `TreeShapeException`), each `message` designed for verbatim LLM feedback. This closes the structured-error gap this decision opened.

## Decision 6 — Extension vocabularies join the core registry through lenny's extension contract

The codegen'd core registry is not the whole vocabulary. Per lenny register A1 (`com.nicospencer/lenny/docs/adrs/0000-ai-decision-register.md`), registration must compose with lenny's **extension contract** — the pure-Dart **`exploration_contract`** package (`plugin.dart` / `types.dart` / `registry.dart` / `plugin_context.dart`) — the seam by which extensions contribute their own node vocabularies, schemas, and `ext.exploration.*` surfaces. *(The `plugin.dart` / `plugin_context.dart` file names here are lenny's on-disk artifacts, quoted verbatim; A21's "extension, never plugin" rule governs memento.engineering's own names — lenny runs its own plugin→extension sweep (bead `lenny-4tvb`) in its repo. The genesis-side seam name, per A19/A21, is `CatalogExtension`.)* Decisions 3 and 4 are what make that composition mechanical rather than aspirational: an extension ships a catalog; the same generator (catalog-generic, provenance-parameterized, registry-parameterized) emits its registry and tool-schema fragment; registration merges them into the core through `exploration_contract`'s `registry.dart`. Retrieval/search over a large multi-extension catalog stays **parked** per lenny A1 — eat the context now, optimize later.

Boundary note: lenny A1 is pending in *lenny's* register and ratifies there; this ADR records only the genesis-side requirement that the registry expose the composition seam.

## Decision 7 — The as-built `genesis_taxonomy` surface: catalog format, pure-A2UI-v0.9 tool schema, executed conformance

*Added 2026-06-13 — promoted from register A19 (`genesis_taxonomy` as-built, commit `2e8aaa2`, 73/73 tests, adversarially verified). Decisions 1–6 set the mechanism; this decision records the shipped surface and the binding directives Nico ratified with it.*

**Catalog format.** A catalog is a JSON document of shape `{catalog: {name, version, description?}, types: {...}}`. The `catalog` block parameterizes every generated header (seam 2); each entry under `types` is one node species. Type-level keys are exactly `description` / `container` / `props` / `dart`; everything else is extension vocabulary (Decision 4 seam 1). Props are typed (`string` / `integer` / `number` / `boolean` / `enum`) and are either `required` or **optional-with-`default`** (Decision 5 as-built).

**Tool schema is pure A2UI v0.9.** The generated `.g.json` is the full A2UI v0.9 `updateComponents` envelope, JSON Schema draft 2020-12, descriptions/types/defaults/required flowing through, `children` on containers only (leaves forbid it via `additionalProperties: false`). The spike's non-standard `rootId` schema extension is **NOT carried** — **ratified pure A2UI v0.9, `rootId` stays dropped** (Nico 2026-06-13; this is the binding directive `genesis_dialogue`/ADR-0003 builds against). Note `buildSeedTree`'s `rootId` *parameter* (Decision 4 seam 3) is the runtime entry-point convention (`'root'`), distinct from the dropped *schema* extension.

**Conformance is validator-executed.** The tool schema is no longer asserted by hand — `genesis_taxonomy` runs the generated schema through the `json_schema` validator (draft 2020-12) on both accept and reject paths, closing the "never-executed conformance" flag this ADR carried.

**Deferred (ledgered in the package README):**
- **A2UI standard-catalog alignment** (`Text` / `Column` / `Button`, v0.9 `createSurface.catalogId`) — owned by the `genesis_dialogue` envelope boundary; this package stays catalog-generic.
- **Per-instance actions** — the catalog declares type-level affordances ("what CAN this afford"); A2UI v0.9 wires actions per instance. Instance wiring is `genesis_dialogue`/`genesis_consent` territory (the consent boundary).
- **Real Dart-enum mapping** — catalog `enum` props bind as validated `String`s today; a value-mapping to real Dart enums is a future binding extension.

---

## Alternatives considered

- **`dart:mirrors` registry** — rejected: unavailable under AOT/Flutter, semi-abandoned upstream, defeats tree-shaking; would fork the implementation by target, which is the exact non-uniformity A2 exists to avoid.
- **Wait for Dart macros** — not available to wait for: cancelled. There is no in-language metaprogramming path.
- **Two hand-maintained sources** (registry written by hand, tool schema written by hand) — rejected: drift between what the LLM is told it can author and what construction accepts is precisely the bug class one-source-codegen kills, and the byte-determinism check (Decision 1) is only possible with a single source.
- **Runtime catalog interpretation** (ship `catalog.json`, build factories dynamically) — rejected: loses construction-time typed validation and tree-shaking; the vocabulary would be stringly-typed at runtime on every target.
- **Keep the script generator in production** — rejected per the A6 conventions (ADR-0001 Foundations); the spike's script form is recorded as a divergence in Decision 5, with the core already factored for the build_runner move.

---

## Register provenance

This document promotes the entries below from `genesis/docs/adr/ADR-0000-ai-decision-register.md`; the register keeper flips their status separately (this pass does not edit ADR-0000):

| Entry | Title | Status |
|---|---|---|
| **A2** (2026-06-11) | Node vocabulary is schema-first + codegen; `dart:mirrors` dropped *(migrated from lenny A1)* | pending → promoted → ADR-0002 (ratified Nico 2026-06-11) |
| **A17** (2026-06-12) | Roadmap package names — codegen/catalog = **`genesis_taxonomy`** (replaces `tree_codegen`) | decided Nico 2026-06-12 — folded 2026-06-13 (Status/Deciders + Decisions 3–7) |
| **A19** (2026-06-12) | `genesis_taxonomy` as-built API surface | ratified Nico 2026-06-13 — folded 2026-06-13 (Decisions 4, 5, 7) |
| **A21** (2026-06-12) | Terminology: "extension", never "plugin" | decided Nico 2026-06-12 — folded 2026-06-13 ("plugin" wording swept; seam is `CatalogExtension`) |

Cited but **not** promoted here: genesis **A6** (house conventions — promotes via ADR-0001 Foundations), genesis **A3** (wire grammar — ADR-0003 A2UI wire format), genesis **A5** (affordances/enforce-reject — ADR-0005 Projection/action substrate), and **lenny register A1** (extension-contract composition — lives in lenny's register and is ratified there, not here). Genesis **A7** is untouched and stays open.

Evidence provenance: all spike citations refer to **untracked working-tree state** under `com.nicospencer/lenny/spikes/` (spike 3: `spike3_schema_roundtrip/` + `spike3_flutter_harness/`; spike 5: `spike5_action_roundtrip/`; verdicts in `RESULTS.md`). Re-run commands are in each spike's `NOTES.md`. Verify before the spike tree is cleaned up.
