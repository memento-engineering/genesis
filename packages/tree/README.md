# genesis_tree

The engine: a framework-agnostic, **bare-VM** `Component` → `Element` keyed-reconcile
tree — Flutter's element/reconciliation model extracted to pure Dart, with no
`dart:ui` and no Flutter dependency.

`genesis_tree` is the shared substrate the rest of [genesis](https://github.com/memento-engineering/genesis)
is built on. It owns the spine and refuses everything else.

## The spine

| Type | Role |
|---|---|
| `Component` | immutable configuration (the Widget analogue) — `createElement()`, `key`, `canUpdate` |
| `Element` | the mounted, persistent node (the Element analogue) — identity, lifecycle, keyed reconcile, dirtiness, one abstract `performRebuild` hook |
| `BuildContext` | a **separate** capability handle passed to `build()` — never the `Element` itself, so a handle held across an async gap fails loudly instead of acting on a stale node |
| `BuildOwner` | the scheduler — drains the dirty set depth-ordered; `flush()` returns the elements it rebuilt |

Reconciliation is by **key/identity**, not structural diff: whole-(sub)tree
re-emission becomes an identity-preserving patch (matched keys keep their
`Element` instance and live state; an `identical()` component prunes its subtree).

## Keys

`Component.key` is a first-class `Key` (not a bare `Object`), so reconciliation
identity carries intent and type-safety:

- `ValueKey<T>(value)` — value `==`/`hashCode`; the type parameter is part of
  identity, so `ValueKey<int>(1)` never collides with `ValueKey<num>(1)`.
  `const Key('id')` is the ergonomic shorthand for `ValueKey<String>('id')`.
- `ObjectKey(value)` — identity equality, to tell apart two objects that are
  equal by `==`.

`Key` is **open** — define your own kinds by extending it. There is
**deliberately no `GlobalKey`**: cross-tree lookup is refused so the tree stays
one-way (cross-boundary references pass handles down through the parent, never
through a global registry). A genuine global-lookup need would be a separate,
explicit, opt-in mechanism — never the default key.

## Composition layer (experimental)

A thin composition layer on the spine, **experimental** and subject to change
before 1.0:

- `StatelessComponent` / `StatefulComponent` + `State` — the build-a-child-Component elements;
- `InheritedComponent` — ambient values down the tree
  (`dependOnInheritedValueOfExactType` to subscribe,
  `getInheritedValueOfExactType` for a dependency-free snapshot — the
  `initState` read);
- `InheritedModel` — the same, scoped by ASPECT: a dependent subscribes
  with `dependOnInheritedValueOfExactType<T>(aspect: a)` and rebuilds only for
  changes `updateShouldNotifyDependent` reports as touching its aspects; omit
  the aspect to depend on the whole value;
- `Watch<T>` — a stream → rebuild builder;
- `HookComponent` — a **hooks-style** stateful primitive (`useState` → `StateCell`,
  `useStream`, `useEffect`, `useMemo`): one class, state declared inline in
  `build`, no separate `State` class. Additive — `State<T>` and `Watch` stay;
- `MultiChildComponent` — a config-declared multi-child container, keyed-reconciled
  through the engine's `updateChildren` (fans out horizontally);
- `SingleChildStatelessComponent` / `SingleChildStatefulComponent` + `Nest` — the
  single-child *chain* vocabulary: each link wraps the next, and `Nest` stacks
  a list of links into a vertical spine down to one leaf (composes vertically).

## Element purity invariant

`Element` stays exactly **identity + keyed reconcile + dirtiness + one abstract
rebuild hook**. It refuses the accretion that bloated Flutter's `Element` — no
rendering, gestures, `addPostFrameCallback`-shaped lifecycle callbacks, timers,
or listeners on the base. Build, state, effects, and scheduling live in
composition subclasses or domains. (Inherited-value propagation is the one
sanctioned base exception — a structural tree-query, lazily allocated.)

## The artifact layer — deliberately not shipped

Flutter's stack is `Widget` (immutable config) → `Element` (persistent
lifecycle + reconcile) → `RenderObject`: the layer of persistent artifacts
that does the real work. `genesis_tree` ports the first two and **stops on
purpose**. It reconciles desired state into live identity; **what that
identity spawns and owns — the artifact layer — is the consumer's**, not the
framework's.

Flutter **bundles** its artifact layer and fixes its shape: `RenderObject`
nodes, a `PipelineOwner`, the layout/paint/hit-test protocol, and
`Theme`/`MediaQuery` ambient scopes are all framework. `genesis_tree`
**unbundles** those four pieces; each is yours to define:

| Piece | Flutter's bundled choice | Yours to define |
|---|---|---|
| **Artifacts** | `RenderObject` | whatever desired state should spawn — the persistent objects your elements create and own |
| **Owner** | `PipelineOwner` | the scheduler for your artifact pass, beside `BuildOwner`'s build pass |
| **Protocol** | layout / paint / hit-test | the pass your artifacts run — layout, observation, resource reconcile |
| **Affordance scopes** | `Theme` / `MediaQuery` | the ambient values your artifact layer reads — `InheritedComponent`s you define |

Two worked examples live in the genesis workspace:

- **`genesis_typesetting`** — typeset cell artifacts + a layout/paint pass onto
  a character grid (the closest analogue to Flutter's render tree);
- **`genesis_perception`** — measurement nodes + a harvest pass that serializes
  an observation instead of painting pixels.

Unlike Flutter's, the layer has **no required shape** — from `genesis_tree`'s
perspective it is not a tree, or anything else in particular. Artifacts can
hang off elements individually, with relationships carried by the element tree
and inherited values; or they can form their own linked structure, up to and
including a full second tree (`RenderObject`'s choice). Earn structure from a
concrete domain problem: build a linked layer only when you can name a
relationship the element tree can't carry — a parent that must enumerate,
meter, or re-parent its artifacts directly. Don't contort to avoid it, and
don't build it for Flutter-symmetry either.

This is the flip side of the purity invariant above: `Element` is
artifact-agnostic — it refuses render and effect machinery precisely so that
any domain — a terminal renderer, a measurement harness, a process supervisor
reconciling live resources — can spawn its own artifact layer from the same
spine.

## Status

Pre-1.0. The spine (`Component`/`Element`/`BuildContext`/`BuildOwner`/keyed reconcile)
is stable in shape; the composition layer is **experimental** and may change.

## License

[BSD-3-Clause](LICENSE).
