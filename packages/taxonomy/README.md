# genesis_taxonomy

Schema-first node vocabulary: one **catalog** classifies the node
species of a domain; codegen emits two projections from it —

1. **the typed Dart factory registry** (`.g.dart`) — a `ComponentRegistry`
   binding wire type names to `Seed` constructors, validating at
   construction time (unknown type, missing/mistyped/unknown prop, invalid
   enum value, children on a leaf), every failure a structured
   `TaxonomyException` an agent loop can feed back to an LLM verbatim;
2. **the LLM-facing tool schema** (`.g.json`) — a JSON Schema
   (draft 2020-12) for authoring an A2UI v0.9-shaped `updateComponents`
   message against the catalog, with prop types / descriptions / defaults /
   required flags flowing through, `children` on containers only, and action
   affordances surfaced as `x-actions` + prose.

Both projections are byte-deterministic (types sorted by name, props in
catalog order, no timestamps; Dart output formatted with `dart_style`), so
the registry the runtime constructs from and the schema the LLM authors
against cannot drift — the generator-in-sync byte-equality test is the
standing guard on committed artifacts.

## Catalog format

A catalog is a JSON document (`*.catalog.json`):

```json
{
  "$comment": "free-form, ignored",
  "catalog": {
    "name": "fixture",          // parameterizes every generated header
    "version": "0.1.0",
    "description": "optional"
  },
  "types": {
    "gauge": {
      "description": "Flows to the tool schema verbatim.",
      "container": false,        // containers carry children; leaves reject them
      "props": {
        "label":   { "type": "string",  "required": true,  "description": "..." },
        "value":   { "type": "number",  "required": true,  "description": "..." },
        "scale":   { "type": "integer", "required": false, "default": 10, "description": "..." },
        "enabled": { "type": "boolean", "required": false, "default": true, "description": "..." },
        "align":   { "type": "enum", "values": ["start", "center", "end"],
                     "required": false, "default": "start", "description": "..." }
      },
      "dart": {
        "class": "Gauge",                    // the Seed subclass to construct
        "import": "fixture_seeds.dart",      // package: or relative to the .g.dart
        "positionalProps": ["label"],
        "namedProps": ["value", "scale", "enabled", "align"],
        "childrenParam": "children"          // containers only
      },
      "actions": {                           // extension vocabulary (see below)
        "set": { "description": "Overwrite ... with context.value." }
      }
    }
  }
}
```

Rules the parser enforces loudly (structured `CatalogFormatException`s with
the document path):

- prop `type` is one of `string` / `integer` / `number` / `boolean` /
  `enum` (JSON Schema vocabulary; `number` binds to Dart `double`, integral
  values widen; `enum` needs a non-empty `values` list and binds as a
  validated Dart `String`);
- props are **required** or **optional-with-default** — optional without
  `default` is rejected, as is a default whose type (or enum membership)
  doesn't match;
- `dart.positionalProps` + `dart.namedProps` must cover exactly the declared
  props; `dart.childrenParam` exactly when `container` is true.

## The extension seam (loud unknown keys)

The core format owns only `description` / `container` / `props` / `dart` at
the type level. **Any other type-level key must be claimed by a registered
`CatalogExtension`, or parsing fails with `UnhandledCatalogKeysException`
listing every unhandled key** — unknown vocabulary is never silently dropped
(the silent-key-drop failure mode this seam exists to kill).

The `actions` block itself rides this seam as the proof:
`ActionsCatalogExtension` (in `defaultCatalogExtensions`) parses it into
`ActionDeclaration` data on `CatalogType.actions` and projects it into the
tool schema (`x-actions` + description prose). Affordances are carried as
data here; `genesis_consent` consumes them for hit-test routing.

## Consuming the generator

**Via build_runner** (the production path): depend on
`genesis_taxonomy`, drop a `<name>.catalog.json` anywhere build_runner looks
(`lib/`, `test/`, ...), and run:

```bash
dart run build_runner build
```

The builder (auto-applied to dependents) emits `<name>.g.dart` +
`<name>.g.json` next to the catalog, `build_to: source`, so artifacts are
committed and the in-sync test guards them.

**Programmatically** (no build_runner required): the builder is a thin shell
over the pure core —

```dart
final outputs = generateFromCatalog(catalogJson); // parse + both emitters
final catalog = Catalog.parse(catalogJson);       // or stepwise
final registryDart = emitRegistry(catalog);
final toolSchemaJson = emitToolSchema(catalog);
```

The shipped builder runs with `defaultCatalogExtensions`; a domain needing
custom extensions wraps `generateFromCatalog(json, extensions: [...])` in its own
builder.

## Building trees through the registry

`buildSeedTree(registry, components, {rootId})` turns a flat keyed component
list into a `Seed` tree **through a registry passed as a parameter** — it
never imports a generated file (the one line a consumer would otherwise have
to fork, now a seam). Component ids become `Seed` keys, so whole-tree
re-emission reconciles to an identity-preserving patch. Tree-shape violations
(duplicate id, unknown root, dangling child, cycle) throw structured
`TreeShapeException`s. Envelope parsing (`updateComponents` itself) is wire
vocabulary and lives with `genesis_dialogue`, which hands the flat list to
this builder.

## Deferred

- **A2UI standard-catalog alignment** (`Text` / `Column` / `Button`, v0.9
  `createSurface.catalogId`) — the `genesis_dialogue` boundary owns the
  envelope and any standard-catalog mapping; this package stays
  catalog-generic.
- **Per-instance actions** — real A2UI v0.9 wires actions per instance via a
  component's `action` property; the catalog declares type-level affordances
  only ("what CAN this afford"). Instance wiring is `genesis_dialogue` /
  `genesis_consent` territory.
- **Extra extension projections** — a third artifact
  (`actions.g.dart`, the Perception-class -> wire-type map for the action
  router's hit-test). The extension seam currently projects into the tool
  schema only; an emit-side artifact hook lands with `genesis_consent`,
  which owns that file's consumer.
- **Dart-enum bindings** — catalog `enum` props bind as validated `String`s;
  a value-mapping to real Dart enums is a future binding extension.
