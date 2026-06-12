# Spike 5 — A2UI action round-trip, setState flavor

Status: **GREEN** — all 9 tests pass on the bare VM (`dart test`):
(a) affordance discoverability, generator-in-sync, (b) enforce + exact-subtree
invalidation, (b2) microtask auto-flush, (c) unknownComponent, (d)
undeclaredAction, (d2) badPayload, (e) staleness, (f) last-write-wins.

## What was proven

### Genesis A5 — validation/invalidation = enforce/reject; "action validation == hit-testing"

The full round-trip closes: catalog -> generated tool schema (LLM authors a
surface) -> wire `updateComponents` -> live mounted perception tree ->
client-fired A2UI v0.9 `action` message -> INTENT -> hit-test against the
LIVE tree -> ENFORCE or REJECT.

- **Affordances are catalog data and they reach the LLM.** The catalog's
  per-type `actions` map (spike5 extension) is projected into the generated
  tool schema twice: structurally as an `x-actions` keyword on the button
  variant, and as prose in the variant description ("AFFORDS CLIENT ACTIONS:
  ... sourceComponentId ... \"press\" ..."). An LLM reading only the tool
  schema can discover which components afford which actions and how to
  address them (test a). Non-actionable types (label, panel) declare nothing.
- **Action validation IS hit-testing, in three catalog/tree-derived gates,
  none hardcoded** (lib/action_router.dart):
  1. the target `sourceComponentId` resolves to a MOUNTED element by walking
     the live tree fresh on every route call (no cached element refs);
  2. the live element's catalog type declares the action name — looked up in
     generated, catalog-derived data (`componentActions` +
     `wireTypeOfPerception` in actions.g.dart), so the affordance check and
     the LLM-visible affordance declaration share one source of truth;
  3. the payload (`context`) validates against the action's contract
     (delegated to the target state).
- **ENFORCE invalidates exactly the target subtree.** A valid `press` is
  applied via the target `PerceptionState.perceived()`: the mutation is
  synchronous, the rebuild flows through markNeedsHarvest -> owner dirty set
  -> flushHarvest. Builder-invocation counters prove the target button's
  builder ran again and the unrelated button's builder did NOT (test b), and
  that the harvest drains (second flush is a no-op). `onNeedsHarvest` wired
  to a scheduleMicrotask flush drains without any manual call (test b2).
- **REJECT is structured and side-effect-free.** Four reasons:
  `unknownComponent` (never existed in any emission), `staleUnmounted`
  (existed, projection moved), `undeclaredAction` (live component, action
  not in its catalog type), `badPayload` (declared action, invalid context).
  Every rejection path is asserted to leave the tree **byte-for-byte
  untouched** via a canonical live-tree dump (config props AND live state)
  captured before/after, plus zero builder invocations and an empty dirty
  set (tests c, d, d2, e).
- **Staleness (the A8 agent-async-gap case).** A v2 whole-tree re-emission
  through the SAME wire path removes the button; keyed reconcile unmounts
  exactly it while survivors keep element identity AND live counter state
  (the v2 reconcile itself runs zero builders). The previously-valid action
  then rejects as `staleUnmounted`, distinguishable from `unknownComponent`
  because the surface keeps an ever-seen id set across emissions. "The
  projection moved under the actor" is therefore a first-class, detectable
  rejection — exactly what genesis A8 needs to feed back to the agent
  (test e).

### Last-write-wins probe (parked multi-party-consensus decision)

Observed semantics with the setState flavor (test f):

- Writes apply **synchronously at route time, in arrival order**. Two `set`
  actions routed back-to-back both return Applied with honest change records
  (`0->5`, then `5->9`): the second write SAW the first's result and
  overwrote it. Final state == LAST write. No merge, no conflict object, no
  rejection of the loser.
- A flush between the writes changes nothing about the outcome (3 then 7 ->
  7). LWW falls out of "state is a single mutable cell + synchronous
  in-order application"; nothing had to be built to get it.
- The dirty set **coalesces** racing writes into one rebuild per flush: two
  unflushed writes -> ONE builder invocation showing only the final value.
  An observer of the rendered projection never sees the intermediate write.
  If consensus ever needs "every applied write is observable", LWW-with-
  coalescing is NOT that — the change records on the Applied results are the
  only audit trail of the intermediate state. Recommendation for the parked
  call: lean LWW (it is the zero-mechanism default and the Applied/Rejected
  results already carry from/to provenance), and treat observable-
  intermediate-states as a separate, explicitly-funded requirement if it
  ever appears.

### Generator-reuse feedback (genesis A2)

spike3's `generateFromCatalog` ran UNCHANGED against a second catalog
(spike5's: panel/label/button) and produced a correct registry binding Dart
classes from THREE packages — `Node` (package:perception), `Field`
(spike3, reused leaf), `CounterButton` (spike5-local StatefulPerception).
Import parameterization (package: and relative) just worked. That cross-
catalog, cross-package reuse is itself A2 evidence. Gaps found, exactly the
genesis-relevant kind:

1. **No extension point for catalog vocabulary the core doesn't know.**
   `_CatalogType` silently ignores unknown type-level keys, so spike5's
   `actions` declarations would have been DROPPED from the tool schema. The
   wrapper (lib/src/generator.dart) had to post-process the generated JSON
   (decode, inject `x-actions` + description prose, re-encode) and emit a
   third projection (actions.g.dart) itself. Production builder (A6) wants
   either first-class action affordances in the catalog format or a
   projection-plugin seam. Silent dropping is the worst failure mode — the
   spike3 core throws loudly on unsupported PROP shapes but not on unknown
   TYPE-level keys.
2. **Provenance headers are hardcoded constants** ("by tool/generate.dart
   (spike3)", title "updateComponents (spike3 catalog)", description "the
   spike3 catalog") — the wrapper string-replaces them to keep committed
   artifacts honest. The generator should take a catalog/package name
   parameter (it's even IN the catalog JSON: `"catalog": "spike5"` — unused).
3. **The wire tree-builder is not reusable across catalogs** — the one
   MINIMAL FORK in this spike (lib/src/wire5.dart). spike3's
   `buildPerceptionTree` hardcodes `import 'generated/registry.g.dart'` and
   calls the free function `buildComponent`; there is no way to point it at
   another catalog's registry. Forked line-for-line, re-bound to spike5's
   registry. Fix for genesis: parameterize the builder over the component
   factory, or generate it per catalog next to the registry. (Envelope
   parsing — `SurfaceUpdate.fromJson`/`ComponentSpec` — reused unchanged.)
4. spike3's string-prop/required-only limits were not hit (spike5's catalog
   stayed inside them by design); the `press` amount/`set` value being
   action-context (not props) is what made integer payloads possible without
   touching the generator. Catalogs that need typed PROPS still block on the
   spike3 limitation already ledgered there.

Determinism/provenance carried over: the same generator-in-sync check style
as spike3 (regenerate in memory, byte-compare all three committed .g files).

### Perception framework feedback (incidental)

- `PerceptionElement` has no `visitChildren`; the live-tree walk dispatches
  on known element shapes (`NodeElement.children`, `ComponentElement.child`
  — both test-only getters). Production wants a real traversal API.
- Updating a `ComponentElement`'s config via keyed reconcile does NOT re-run
  its builder (no rebuild-on-update); for this spike that was an asset
  (re-emission provably runs zero builders) but it means config changes to a
  stateful component are invisible until something else dirties it — worth a
  decision before genesis builds on it.

## Re-run commands (from the repo root)

```bash
(cd spikes/spike5_action_roundtrip && dart pub get)
dart run spikes/spike5_action_roundtrip/tool/generate.dart
(cd spikes/spike5_action_roundtrip && dart test)
```

Dart 3.12.0.

## Action-message fidelity ledger

Source consulted (live, 2026-06-11): a2ui.org A2UI v0.9 spec page
(https://a2ui.org/specification/v0.9-a2ui/). The Message Reference page
(https://a2ui.org/reference/messages/) documents ONLY server->client
messages (createSurface, updateComponents, updateDataModel, deleteSurface)
— no client->server shapes there.

**Mirrored (matches real A2UI v0.9 per the spec page):**

- Client->server message type is `action` with required fields `name`
  (string), `surfaceId` (string), `sourceComponentId` (string), `timestamp`
  (ISO 8601 string), `context` (object). `ActionMessage` uses exactly these
  field names; `sourceComponentId` is the back-reference to the component,
  which is what makes hit-testing by component id the natural validation.
- Server->client surface emission reuses spike3's v0.9-shaped
  `updateComponents` envelope unchanged (see spike3's ledger).

**Diverged (spike simplifications/extensions):**

- **Envelope nesting unverified**: the spec page shows the action message's
  fields but the page as fetched did not show the client->server transport
  envelope. The spike parses `{"action": {...}}` (by analogy with
  server->client messages keyed by message type) AND a bare action object.
- **Affordance declaration site**: real A2UI v0.9 declares actions
  per-INSTANCE via a component's `action` property
  (`{"event": {"name": ..., "context": ...}}` or a local `functionCall`),
  i.e. the surface author wires the action name. Spike5 declares affordances
  at the catalog TYPE level (`actions: {press, set}`) and validates the
  fired name against the type — the genesis A5 framing. A production
  implementation likely needs both: type-level "what CAN this afford" (tool
  schema, hit-test) and instance-level "what does this emission wire up".
  The spike's `context` is the action message's payload, not an echo of an
  instance-declared context object — closest divergence to flag.
- `timestamp` is parsed leniently (accepted, never validated) and unused in
  routing; ordering is purely arrival order. A real consensus story might
  use it — the LWW probe deliberately did not.
- No `functionCall` (client-local) actions, no data model (`/path`)
  references, no `updateDataModel`/`deleteSurface` — out of scope.
- Rejections are returned to the caller as Dart values; A2UI does not (per
  the pages reached) define a server->client "action rejected" message, so
  the structured Rejection shape here is spike-local vocabulary for the
  genesis A5/A8 feedback loop.

## Divergences from production (deliberate spike shortcuts)

- The router reaches the target state via the test-only
  `StatefulElement.state` getter and an `ActionableState` interface;
  production wants a first-class action-dispatch seam on elements.
- `everSeenIds` grows forever (fine for a spike; production staleness
  tracking needs eviction/versioning — e.g. surface generation counters).
- Build counters are a global map keyed by component id
  (lib/src/components.dart), reset per test.
- Surface/owner lifecycle is single-surface, single-owner; `surfaceId`
  mismatch is folded into `unknownComponent` rather than its own reason.
- Spike package is untracked and resolved independently of the pub
  workspace; path-deps on packages/perception and on spike3 (verified
  pattern from earlier spikes).
