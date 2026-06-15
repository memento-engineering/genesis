# genesis_tree

The engine: a framework-agnostic, **bare-VM** `Seed` → `Branch` keyed-reconcile
tree — Flutter's element/reconciliation model extracted to pure Dart, with no
`dart:ui` and no Flutter dependency.

`genesis_tree` is the shared substrate the rest of [genesis](https://github.com/memento-engineering/genesis)
is built on (ADR-0001). It owns the spine and refuses everything else.

## The spine

| Type | Role |
|---|---|
| `Seed` | immutable configuration (the Widget analogue) — `createBranch()`, `key`, `canUpdate` |
| `Branch` | the mounted, persistent node (the Element analogue) — identity, lifecycle, keyed reconcile, dirtiness, one abstract `performRebuild` hook |
| `TreeContext` | a **separate** capability handle passed to `build()` — never the `Branch` itself (ADR-0001 A8), so a handle held across an async gap fails loudly instead of acting on a stale node |
| `TreeOwner` | the scheduler — drains the dirty set depth-ordered; `flush()` returns the branches it rebuilt |

Reconciliation is by **key/identity**, not structural diff: whole-(sub)tree
re-emission becomes an identity-preserving patch (matched keys keep their
`Branch` instance and live state; an `identical()` seed prunes its subtree).

## Composition layer (experimental)

A thin composition layer on the spine, **experimental under the two-consumer
rule** (it freezes only once perception and an expression surface both consume
it):

- `StatelessSeed` / `StatefulSeed` + `State` — the build-a-child-Seed elements;
- `InheritedSeed` — ambient values down the tree (`dependOnInheritedSeedOfExactType`);
- `Watch<T>` — a stream → rebuild builder;
- `Sprout` — a **hooks-style** stateful primitive (`useState` → `StateCell`,
  `useStream`, `useEffect`, `useMemo`): one class, state declared inline in
  `build`, no separate `State` class. Additive — `State<T>` and `Watch` stay.

## Branch purity invariant

`Branch` stays exactly **identity + keyed reconcile + dirtiness + one abstract
rebuild hook**. It refuses the accretion that bloated Flutter's `Element` — no
rendering, gestures, `addPostFrameCallback`-shaped lifecycle callbacks, timers,
or listeners on the base. Build, state, effects, and scheduling live in
composition subclasses or domains. (Inherited-value propagation is the one
sanctioned base exception — a structural tree-query, lazily allocated.) See
ADR-0001 Decision 3.

## Status

Pre-1.0. The spine (`Seed`/`Branch`/`TreeContext`/`TreeOwner`/keyed reconcile)
is stable in shape; the composition layer is **experimental** and may change.
Design rationale: `docs/adr/ADR-0001-foundations.md` in the monorepo.

## License

[BSD-3-Clause](LICENSE).
