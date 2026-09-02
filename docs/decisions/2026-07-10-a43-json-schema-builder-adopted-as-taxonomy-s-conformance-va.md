---
status: accepted
date: 2026-07-10
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a43-json-schema-builder-adopted-as-taxonomy-s-conformance-va
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A43"
---
## A43 (2026-07-10) — `json_schema_builder` adopted as taxonomy's conformance validator, NOT as its schema emitter (A26 item 3, evaluated)  ·  AI

**Decision (bead `genesis-6l8`, the "optional/modest" A26 item 3):** split the swap. **Adopt** `json_schema_builder` (labs.flutter.dev `0.1.5`, the draft-2020-12 lib `a2ui_core` + `genai_primitives` build on) as the **test-side conformance validator** in `genesis_taxonomy`, replacing the unrelated `json_schema` dev-dep. **Do NOT** rewrite the emitter (`lib/src/tool_schema_emitter.dart`) onto its typed builders — the hand-assembled `Map<String, Object?>` stays. So of the two surfaces the bead named ("hand-assembled map + the json_schema dev-dep"), only the validator is swapped; the emitter is deliberately kept.

**Why keep the emitter hand-assembled:** the schema's distinguishing features are exactly what the typed builders do *not* model, so adoption would not remove hand-assembly — it would only fragment it. (1) `Schema.object`/`ObjectSchema` expose no `$comment` (our GENERATED-provenance line), no `$schema` (dialect declaration), and no arbitrary `x-` keyword — but the catalog-**extension** seam (`CatalogExtension.augmentToolSchemaVariant`) injects `x-actions` **and** mutates the variant `description` in place by writing raw map keys; that seam is map-shaped by contract and would stay raw-map poking regardless. (2) `ObjectSchema`'s factory leads its map with `type` and has no slot for `$comment`/`$schema`, so forcing the top-level envelope through it either reorders keys — churning the deterministic golden `.g.json` fixture that downstream consumers commit — or hand-builds the top-level map anyway, defeating the point. (3) props carrying a `default` can't use `Schema.string`/`.integer`/`.boolean` (none take `defaultValue`), only `Schema.combined(type: JsonType…, defaultValue:…)`, which is longer and mixes idioms versus today's uniform `_propSchema` one-liner. Net for emit: mixed typed-builder + raw-map code, fixture-churn risk, zero functional gain — a readability/determinism regression, so declined.

**Why adopt the validator (clean win):** it is the *exact* draft-2020-12 validator the genui A2UI ecosystem runs, so "our hand-emitted schema validates" now means "an A2UI client built on `a2ui_core` would accept it" — the interop-conformance thesis of A26, turned from claim into executed evidence. Mechanically frictionless: `json_schema_builder`'s `Schema` is an **`extension type` over `Map<String, Object?>`** (zero-cost; its own docs say to `Schema.fromMap` a raw map for anything the typed factories don't cover), so the oracle wraps our emitted map directly with no adapter. Its `validate()` is **async** (`Future<List<ValidationError>>`, empty ⇒ valid) — the only test change; all 10 conformance cases pass identically (accept + every reject path: missing-required, leaf-`children`, unknown-prop, wrong-type, non-integer, enum-out-of-set, unknown-component, wrong-envelope-version), confirming `oneOf` + `const` discriminators + `additionalProperties:false` behave the same as under `json_schema`.

**Affects:** `genesis_taxonomy` dev-deps only — `json_schema ^5.2.2` → `json_schema_builder ^0.1.5` (also drops transitive `quiver`/`rfc_6901`/`uri`); `test/tool_schema_test.dart` (validator import + the conformance group goes async). Emitter, public API, runtime deps, and the `.g.json` golden output are **unchanged** — dev-only, so no `genesis_taxonomy` version/CHANGELOG bump. This is the concrete outcome of A26 item 3 (partial adopt); A26 items 1/2/4/5 (a2ui_core interop, genai_primitives) are untouched. Adopting a pre-1.0 labs package as a *test* oracle (not a shipped dep) is the low-blast-radius way to buy the ecosystem alignment; revisit the emitter only if a future need makes the schema a runtime `Schema` value rather than a codegen string. **Status:** pending.

