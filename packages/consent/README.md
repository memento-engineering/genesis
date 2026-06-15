# genesis_consent

The enforce/reject action substrate: **action validation IS
hit-testing the live tree**. consent is the world-side end of the agent↔surface
dialogue — `genesis_dialogue` *decodes* a client `action` message into an
`ActionEvent` (parse only); consent *routes* it.

Affordances declare what may be asked; the router grants what the live tree
affords and withholds what it does not. Every refusal is a refusal of consent,
and `staleUnmounted` is consent **revoked because the world changed**.

## What it does

| Piece | API |
|---|---|
| **Router** | `ConsentRouter(surface, catalog)` → `mount` / `apply` / `route` |
| **Outcome** | `ConsentOutcome` = `Applied` \| `Rejected` (sealed; switch exhaustively) |
| **Dispatch seam** | `Actionable` — a domain `State` implements `validateAction` + `applyAction` |

```dart
final surface = DialogueSurface(registry: myRegistry);
final catalog = Catalog.parse(myCatalogJson); // declares the actions
final router  = ConsentRouter(surface: surface, catalog: catalog);

router.mount(parseUpdateComponents(message));        // drive emissions THROUGH the router
final outcome = router.route(parseActionEvent(json)); // hit-test → enforce/reject

switch (outcome) {
  case Applied(:final componentId, :final change):
    // enforced through the target's Actionable handler; change carries from/to provenance
  case Rejected(:final kind, :final message):
    // tree byte-for-byte untouched; feed `message` back to the agent
}
```

Drive emissions through `router.mount` / `router.apply` (not the surface's
directly): the router keeps the ledger the hit-test needs — the ids ever seen,
and the current id→type map — which dialogue's surface does not track. A
renderer can still share the surface's `TreeOwner` to draw the same tree.

## The three gates

An incoming `ActionEvent` is validated by hit-testing the **live** mounted tree,
walked fresh on every `route` call (no cached branch refs):

1. **exists/mounted** — `sourceComponentId` resolves to a mounted branch by
   key; otherwise `staleUnmounted` (ever-seen) or `unknownComponent` (never
   seen);
2. **catalog-declared** — the live component's wire type declares the action in
   the catalog — the *same* `actions` data the LLM saw as `x-actions` in the
   tool schema (one source of truth); otherwise `undeclaredAction`;
3. **payload** — the target's `Actionable` handler validates `context`; a throw
   is `badPayload`.

A valid intent is **enforced** through the target's `Actionable.applyAction` (the
`perceived()`/setState path), so the rebuild flows through the standard
dirty/flush pipeline and **exactly the target subtree** invalidates. Every
rejection is **side-effect-free**: the tree is left byte-for-byte
untouched (config props AND live state), and the structured `Rejected.message`
is the feedback channel back to the actor.

## Affording actions: implement `Actionable` on the element

A component affords client actions when its catalog type declares them
(`"actions": { ... }`) **and** its **element** implements `Actionable`. consent
hit-tests the live tree and dispatches through `branch is Actionable`, so the
seam sits on the element — a component's `State` is `@protected` and out of the
router's reach. The element forwards to its state, which holds the logic:

```dart
class Counter extends StatefulPerception {
  const Counter({super.key});

  @override
  CounterState createState() => CounterState();
  @override
  CounterElement createBranch() => CounterElement(this);
}

// The element is the seam: it implements Actionable and forwards to its state.
class CounterElement extends StatefulPerceptionElement implements Actionable {
  CounterElement(Counter super.seed);
  CounterState get _state => state as CounterState;

  @override
  void validateAction(String name, Map<String, Object?> payload) =>
      _state.validateAction(name, payload);
  @override
  ActionChange applyAction(String name, Map<String, Object?> payload) =>
      _state.applyAction(name, payload);
}

class CounterState extends PerceptionState<Counter> {
  int _count = 0;

  // gate 3 — pure: throw ActionPayloadException on a bad payload, mutate nothing.
  void validateAction(String name, Map<String, Object?> payload) {
    if (name == 'set' && payload['value'] is! int) {
      throw const ActionPayloadException('"value" must be an integer');
    }
  }

  // Enforce via the setState-analogue, never by patching the tree directly.
  ActionChange applyAction(String name, Map<String, Object?> payload) {
    final from = _count;
    perceived(() => _count = payload['value']! as int);
    return ActionChange(from: from, to: _count);
  }
}
```

`validateAction` is kept pure so a `badPayload` rejection is side-effect-free by
construction. `applyAction` mutates through the state's setState-analogue, never
by patching the tree directly — that is what makes "exactly the target subtree
rebuilds" provable.

## Staleness — the agent-async-gap bridge

A whole-tree re-emission (`apply`) that drops a component unmounts exactly it
via keyed reconcile, while survivors keep element identity **and** live state. A
previously-valid intent against the dropped component then rejects as
`staleUnmounted` — distinguishable from `unknownComponent` because the router
keeps an ever-seen id set across emissions. *"The projection moved under the
actor"* is a first-class, detectable outcome, and `Rejected.message` is exactly
the feedback the agent needs.

## Multi-party consensus — parked, lean last-write-wins (Decision 6)

Writes apply synchronously at route time in arrival order; the last write wins,
and the `Applied.change` `from`/`to` records are the audit trail. Two unflushed
writes coalesce into one rebuild — an observer of the rendered projection never
sees the intermediate value. Anything richer (observable intermediate states,
merge semantics) is a separate, explicitly-funded requirement.

## Boundaries

- **No `a2ui_core` dependency**: a2ui_core has no element tree to
  hit-test against and no unmount lifecycle, so it cannot express this layer —
  the enforce/reject substrate is genuinely genesis-native. The only interop
  surface is the action message vocabulary, already aligned in `dialogue`
  (`ActionEvent` ↔ `A2uiClientAction`).
- **Single surface, v1.** A `surfaceId` mismatch folds into `unknownComponent`
  (the component is not on this surface).
- **Dispatch seam.** consent dispatches through the `Actionable` interface a
  component's element implements (`branch is Actionable`), so the tree core
  carries no action vocabulary. A blessed action-dispatch hook in the tree core
  is a possible future refinement (deferred).
- Tests consume `genesis_perception`'s `Node`/`Field` plus a stateful `Counter`
  fixture — no reinvented vocabulary.
