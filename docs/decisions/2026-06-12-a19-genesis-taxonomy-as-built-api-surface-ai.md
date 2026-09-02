---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a19-genesis-taxonomy-as-built-api-surface-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A19"
---
## A19 (2026-06-12) — `genesis_taxonomy` as-built API surface  ·  AI

**Decision (as built, commit `2e8aaa2`; 73/73 tests, adversarially verified incl. seam tampers):**
- **Catalog format:** `{catalog: {name, version, description?}, types: {...}}`; core type-level keys are exactly `description`/`container`/`props`/`dart`; **every other type-level key is extension vocabulary** (seam 1); unknown keys anywhere else → `CatalogFormatException`.
- **Typed props:** `string`/`integer`/`number`/`boolean`/`enum(values)`; `required` stated explicitly; **optional props MUST declare `default`** (both directions enforced at parse); explicit JSON null = absent.
- **Sealed `TaxonomyException` hierarchy** (three families for exhaustive switching: `CatalogException` / `ComponentBuildException` / `TreeShapeException`), messages designed for verbatim LLM feedback — closes ADR-0002's structured-error gap.
- **Extension seam:** `CatalogExtension{name, typeKeys, parseTypeValue, augmentToolSchemaVariant}` *(renamed from `CatalogPlugin` per A21)*; ALL unclaimed type-level keys across the catalog throw once as `UnhandledCatalogKeysException` (loud, lists keys + registered extensions). **Actions ride the seam as the proof** (`ActionsCatalogExtension` → `CatalogType.actions` + `x-actions` in the tool schema — `genesis_consent` consumes later).
- **`ComponentRegistry` runtime lives in the library**; generated files are thin wiring (`componentRegistry` instance per catalog). **Seam 3:** `buildSeedTree(registry, components, {rootId})` — registry is a parameter, never an import; component id → Seed key; cycles rejected with the id path; DAG shares build twice (spike behavior kept).
- **Seam 2:** provenance fully parameterized from the catalog name block; generated Dart post-formatted via `dart_style` (passes the repo format gate); both emitters byte-deterministic.
- **build_runner:** `*.catalog.json` → sibling `.g.dart` + `.g.json`, `build_to: source` with an in-sync test as the guard; the shipped builder runs default extensions only — custom extensions wrap `generateFromCatalog`.
- **Tool schema:** full A2UI v0.9 `updateComponents` envelope, draft 2020-12; the spike's non-standard `rootId` extension was **NOT carried**; conformance is **validator-executed** (`json_schema`, accept + reject paths) — closes ADR-0002's never-executed flag.
- **Deferred (ledgered in README):** A2UI standard-catalog alignment (`genesis_dialogue` boundary), per-instance actions (`genesis_consent` boundary), real Dart-enum mapping.
**Affects:** ADR-0002 at promotion; `genesis_dialogue` consumes `buildSeedTree` + the envelope shape. **Status:** promoted → ADR-0002 D4/D5/D7 (+ ADR-0003 pure-v0.9/`rootId`-dropped direction), 2026-06-13 (commit `cc4bf28`). `CatalogExtension` naming accepted as-built.

