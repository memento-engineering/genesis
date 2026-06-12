# Spike 3 — schema-first codegen + A2UI flat-keyed wire round-trip

Status: **GREEN** — all 5 checks pass on the bare VM (`dart test`) AND under
`flutter test`, calling the exact same check functions.

## What was proven

### Genesis A2 — "schema-first + codegen, no mirrors"

- ONE schema source (`schema/catalog.json`, two types: `node` container,
  `field` leaf, with per-type/per-prop descriptions) drives TWO generated
  projections via `tool/generate.dart`:
  1. `lib/src/generated/registry.g.dart` — typed Dart factory registry
     (`Map<String, Perception Function(props, children, key)>`) that
     validates at construction: unknown type, missing required prop,
     mistyped prop, unknown prop, and children-on-a-leaf all throw
     `StateError` with diagnostics.
  2. `lib/src/generated/tool_schema.g.json` — LLM-facing JSON Schema
     (draft 2020-12) for authoring an `updateComponents` message: type enum
     via per-variant `component` const discriminators, per-type props with
     the catalog's descriptions, `children` present for containers only and
     forbidden for leaves via `additionalProperties: false`.
- Determinism + provenance are enforced by check (a): the generator core is
  importable (`lib/src/generator.dart`), the test re-runs it in memory and
  asserts byte-equality with the files on disk (falsified during the spike:
  appending a stray comment to `registry.g.dart` turned the check red with
  "OUT OF SYNC ... first diff at index 2319"; regenerating turned it green).
- Nothing outside `registry.g.dart` hardcodes component type names — the
  wire deserializer goes exclusively through the generated
  `buildComponent(type, props, children, key)`.
- No mirrors, no `dart:mirrors`, no runtime reflection anywhere.

### Genesis A3 — "A2UI flat-keyed grammar; tree keys == A2UI component IDs; whole-subtree emission reconciles to a patch by key"

- An A2UI-v0.9-shaped flat `updateComponents` message (flat adjacency list,
  `component` discriminator, props on the component object, `children` as id
  arrays) deserializes through the generated registry into a `Perception`
  tree where **component id becomes `Perception.key`** (check b).
- Check (d), the crux: mount v1 (root node + 4 keyed children incl. a nested
  subtree) via `PerceptionOwner.mountRoot`, capture child
  `PerceptionElement` instances, then deserialize a WHOLE-tree v2 re-emission
  (one prop changed, one component removed, one inserted, two reordered) and
  call `rootElement.update(...)`. Asserted with `identical()`:
  - prop-changed id (`f_name`) → SAME element instance, NEW perception
    config object, new prop value visible;
  - reordered ids (`n_addr` 2→1, `f_email` 1→2) → SAME instances at their
    new indices;
  - DEEP identity: the `f_street` element nested inside the moved `n_addr`
    subtree is also the SAME instance;
  - removed id (`f_age`) → old instance unmounted (`.mounted == false`);
  - inserted id (`f_phone`) → fresh, mounted instance.
  Whole-subtree emission therefore reconciles to a minimal,
  identity-preserving patch keyed by component id. The root survives
  re-emission because its id (`"root"`, the v0.9 convention) is a stable key
  and `Perception.canUpdate` holds.
- Rejection paths (check e): dangling childId, duplicate id, cycle, unknown
  rootId (deserializer-level) and unknown type, mistyped prop, missing
  required prop, children-on-leaf (generated-registry-level) all throw.
- Dual harness: `lib/checks.dart` is framework-free (throws `StateError`,
  imports no test framework), so the IDENTICAL functions run under
  `package:test` on the bare VM and under `flutter_test` — same 5 checks
  green in both bindings.

## Re-run commands (from the repo root)

```bash
dart run spikes/spike3_schema_roundtrip/tool/generate.dart
(cd spikes/spike3_schema_roundtrip && dart pub get && dart test)
(cd spikes/spike3_flutter_harness && flutter pub get && flutter test)
```

Flutter binary used: `/Users/nico/flutter/bin/flutter` (3.44.0); Dart 3.12.0.

## A2UI fidelity ledger

Sources consulted (live, 2026-06-11): a2ui.org "Message Reference"
(https://a2ui.org/reference/messages/) and the A2UI v0.9 spec page
(https://a2ui.org/specification/v0.9-a2ui/). The google/A2UI GitHub raw
schema path tried first (specification/json/server_to_client.json) 404'd;
the a2ui.org reference pages were used instead.

**Mirrored (matches real A2UI v0.9):**

- Envelope: `{"version": "v0.9", "updateComponents": {"surfaceId": ...,
  "components": [...]}}` — exact field names and nesting. (v0.9 renamed
  v0.8's `surfaceUpdate` to `updateComponents`; the Dart class is still
  named `SurfaceUpdate` per the spike spec, but the WIRE shape is v0.9.)
- Flat component objects with `component` as a string type discriminator
  and all props at the top level of the component object (v0.9's "flat"
  style, replacing v0.8's nested `{"component": {"Text": {...}}}`).
- `children` as an ordered array of component-id strings (adjacency list).
- Root identified by the convention `id == "root"` (v0.9 has no explicit
  root field in `updateComponents`).

**Diverged (spike simplifications/extensions):**

- `rootId` — optional extension field inside `updateComponents` that
  overrides the `id == "root"` convention. NOT part of A2UI v0.9 (v0.8 had
  `beginRendering.root`; v0.9 dropped it). Defaults to `"root"`, so pure
  v0.9 messages parse unchanged.
- Component vocabulary is the spike catalog (`node`, `field`), not the A2UI
  standard catalog (`Text`, `Column`, `Button`, ...), and the catalog file
  format (`schema/catalog.json`) is spike-local, not the A2UI catalog
  format referenced by v0.9 `createSurface.catalogId`.
- No `createSurface` lifecycle message, no data-binding (`/path` data model
  references), no client->server events — out of scope for this spike.
- `version` is parsed leniently (ignored rather than validated).
- A component reachable twice via different parents (a DAG share) is built
  twice rather than rejected; only true cycles are rejected.

**Unknown / not verified:** exact JSON-Schema text of the official v0.9
catalog definitions (the GitHub raw schema files were not reachable); field
names above are as quoted by a2ui.org reference pages.

## Divergences from production (deliberate spike shortcuts)

- Codegen is a plain `dart run tool/generate.dart` script; production will
  be a build_runner builder (genesis A6). The core is already factored as a
  pure importable function (`generateFromCatalog`) to ease that move.
- Generator supports only `string`-typed, required props and throws on
  anything else (loud failure instead of silent wrong codegen).
- The generated registry returns `StateError`s; production likely wants a
  structured error type the agent loop can feed back to the LLM.
- `checks.dart` locates the package root via
  `Isolate.resolvePackageUriSync` with a `.dart_tool/package_config.json`
  walk-up fallback (the flutter_test environment throws UnsupportedError
  from resolvePackageUriSync — a real cross-binding gotcha worth
  remembering).
- Spike packages are untracked and resolved independently of the pub
  workspace (path dep into `packages/perception` from outside the
  workspace member list), per the spike-phase constraint of not touching
  tracked files.
