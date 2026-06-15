# genesis_dialogue

The A2UI v0.9 wire format: the bidirectional grammar of the
agent↔surface exchange. The agent **authors and re-emits** surfaces; the
surface **reports actions** back. `genesis_dialogue` is the codec + receive
side of that conversation.

It is pure A2UI v0.9: the `updateComponents` envelope (never
v0.8's `surfaceUpdate`), root by the `id == "root"` convention, **no** `rootId`
field.

## What it does

| Piece | API | Direction |
|---|---|---|
| **Codec** | `parseUpdateComponents(json)` → `UpdateComponents`; `UpdateComponents.toJson()` | wire ↔ typed (lossless both ways) |
| **Receive surface** | `DialogueSurface.mount` / `.apply` | wire → live tree, reconciled by key |
| **Action parse** | `parseActionEvent(json)` → `ActionEvent` | wire → typed (parse only) |

## The A2UI v0.9 vocabulary mapping

The envelope, exactly mirrored:

```json
{
  "version": "v0.9",
  "updateComponents": {
    "surfaceId": "main",
    "components": [
      {"id": "root", "component": "node", "name": "form", "children": ["f1"]},
      {"id": "f1", "component": "field", "name": "Name", "value": "Nico"}
    ]
  }
}
```

| Wire | Meaning | Maps to |
|---|---|---|
| `version` | `"v0.9"`, required, strict | rejected if absent or not `v0.9` |
| `updateComponents.surfaceId` | target surface | `UpdateComponents.surfaceId` |
| `updateComponents.components` | flat adjacency list | `List<ComponentInstance>` |
| `component` | string type discriminator | `ComponentInstance.type` → registry key |
| props at top level | flat v0.9 prop style | `ComponentInstance.props` |
| `children` | ordered array of component-id strings (containers only) | `ComponentInstance.childIds` |
| `id` | stable component id | `ComponentInstance.id` → **`Seed.key`** |
| root | the component with `id == "root"` | no `rootId` field on the wire |

The client→server **action** message:

```json
{"action": {"name": "set", "surfaceId": "main",
            "sourceComponentId": "f1", "timestamp": "…", "context": {…}}}
```

maps to `ActionEvent{name, surfaceId, sourceComponentId, payload, timestamp?}`
(`payload` is the wire `context`). Both the `{"action": {…}}` wrapper and a
bare action object are accepted.

## The `genesis_taxonomy` consume boundary (the seam)

`genesis_dialogue` does **not** re-implement deserialization. The deserialize
half already exists in `genesis_taxonomy`:

- `ComponentInstance` — the registry-facing flat shape. dialogue's codec parses
  the wire **into** this type; it does not redefine it.
- `buildSeedTree(registry, components, rootId: 'root')` — turns the flat list
  into a keyed `Seed` tree (component id → `Seed` key; dangling child id,
  duplicate id, cycle, unknown type/prop all rejected there).
- `ComponentRegistry` — the catalog-bound factory. **Injected** via
  `DialogueSurface(registry: …)`: dialogue is registry-agnostic, so the same
  wire layer works against whatever catalog the consumer generated.

What dialogue adds on top: the **envelope parse/serialize** (the outer
`{version, updateComponents:{surfaceId, components}}` message), the
**receive-side surface** (mount + reconcile-by-key), and the **action parse**.

Rejection lives at the layer that owns the invariant:

- **Envelope-level (here):** missing/non-`v0.9` version, missing
  `updateComponents`, non-list components, component missing `id`/`component`,
  duplicate id — all `DialogueException`s with LLM-feedback-ready messages.
- **Deserializer/registry-level (`genesis_taxonomy`):** dangling child id,
  duplicate id, cycle, unknown type, bad/missing props, children on a leaf —
  all `TaxonomyException`s. dialogue does **not** duplicate these.

## Reconcile by key

`DialogueSurface.apply` builds the new keyed `Seed` tree and calls
`rootBranch.update(newRootSeed)`. The root id is `"root"` (a stable key) with
an unchanged type, so `canUpdate` holds, the root updates in place, and its
children reconcile by key. Whole-tree re-emission therefore becomes an
identity-preserving patch: kept ids keep their `Branch` instances (reordered
at their new index, deep into moved subtrees), a prop-changed id keeps its
instance with the new seed, removed ids unmount, inserted ids mount fresh.

**Honest limit (the reconcile fast path).** The reconcile fast path skips
only on `identical()` seeds. Freshly *deserialized* seeds are never
`identical()`, so re-applying a byte-identical message does **not**
short-circuit the reconcile — the wire path does not benefit from it. Keyed
identity preservation still holds; only the skip optimization does not fire.
This is the point of keyed reconciliation, and the `surface_reconcile_test`
fast-path case asserts both halves.

## The action seam → genesis_consent

`parseActionEvent` is **parse only**. It produces a typed `ActionEvent`; it
does not route it, hit-test `sourceComponentId` against the live tree, check
the affordance, or validate the payload. That is `genesis_consent`'s job
(the enforce/reject substrate). An `ActionEvent` crossing this
boundary has been *decoded*, not *authorized*. dialogue owns the wire
vocabulary; consent owns the world-side enforcement.

## Emission boundary

The codec's **serialize** direction (`UpdateComponents.toJson`) *is* emission
of an authored surface — round-trip-proven against the parse. The **reverse**
(walking a live mounted `Seed`/`Branch` tree back into a component list)
needs a `genesis_taxonomy` reverse-describer that does not exist as built, so
it is deferred (below). v1 emission is the authored-representation serialize
path only.

## A2UI v0.9 fidelity ledger

Carried-forward decisions from the wire design, updated for the as-built
dialogue layer.

| Status | Item |
|---|---|
| **Mirrored** | Envelope shape `{version, updateComponents:{surfaceId, components}}`; flat components + string `component` discriminator; props at top level; `children` as ordered id arrays; root by `id == "root"`. |
| **Mirrored** | Action message fields `{name, surfaceId, sourceComponentId, timestamp, context}` (a2ui.org Message Reference); `context` is the payload; `sourceComponentId` is the hit-test back-reference. |
| **Dropped** | The earlier `rootId` extension. There is no wire `rootId` override — root is `id == "root"`, period (pure v0.9). |
| **Diverged** | **`version` is now parsed STRICTLY** (must be present and `== "v0.9"`), where earlier drafts parsed it leniently. The default that keeps pure-v0.9 parsing unchanged: a real v0.9 message always carries `version: "v0.9"`, so it still parses; only a missing/wrong version is now rejected loudly rather than ignored. |
| **Diverged** | Component vocabulary is the consumer's genesis catalog (the test catalog here binds `node`/`field` → perception `Node`/`Field`), not the A2UI standard catalog (`Text`, `Column`, `Button`, …). |
| **Diverged** | The action transport **envelope nesting is unverified** against the spec: the parser accepts both `{"action": {…}}` and a bare action object. |
| **Diverged** | The action message's `timestamp` and `context` are parsed as **optional** (lenient-in: `timestamp` may be absent, `context` defaults to `{}`), where a2ui_core marks both required on `A2uiClientAction`. Well-formed v0.9 actions still parse; this only tolerates a thinner client. |
| **Unknown** | Exact JSON-Schema text of the official v0.9 catalog definitions (the google/A2UI raw schema path 404'd when checked); field names are as quoted by a2ui.org reference pages. |

## Deferred (NOT in v1)

- **Seed-tree → envelope reverse-emission** — walking a live mounted tree back
  into a component list. Needs a `genesis_taxonomy` reverse-describer (a
  `Seed` → `ComponentInstance` projection) that does not exist as built; v1
  does not build it and does not change taxonomy. v1 emission = the
  authored-representation serialize path only.
- **Action routing → `genesis_consent`** — hit-testing, affordance checks,
  payload validation, and applying the action. dialogue produces the typed
  event; consent consumes it.
- **Data binding** — `updateDataModel` and `/path` data-model references
  (v0.9's message, per the a2ui.org reference). The codec carries no data
  model.
- **`createSurface` lifecycle** — surface creation/teardown, `catalogId`. v1
  is `updateComponents` + `action` only.
- **Streaming / incremental** — partial or chunked `updateComponents`
  delivery; v1 parses a whole message.

## Test catalog

`test/src/dialogue_fixture.catalog.json` binds wire types to **real**
`genesis_perception` species — `node` → `Node` (container), `field` → `Field`
(leaf) — and `dart run build_runner build` projects it into the committed
`dialogue_fixture.g.{dart,json}` fixtures. `registry_in_sync_test.dart` is the
standing guard: the committed artifacts must equal an in-memory regeneration
(re-run the builder if it is red). Envelopes in the surface tests therefore
deserialize into real perception `Node`/`Field` trees.

## Run

```bash
dart pub get
dart run build_runner build          # regenerate the test-catalog fixtures
dart analyze
dart test
dart format .
```
