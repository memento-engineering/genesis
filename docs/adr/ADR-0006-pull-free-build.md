# ADR-0006 — Pull-free build: the tree builds synchronously; watch out-of-band

**Status:** Accepted 2026-06-17 (Nico). No prior register entry — surfaced in lenny `lenny-9kni` (the pure-Dart VM-service host) and promoted at Nico's direction. *Re-scoped 2026-06-17, same session, from a perception-specific framing to the `genesis_tree` substrate invariant it actually is — it governs `Seed`/`Branch`, so every domain on the tree inherits it, not just `genesis_perception`.*
**Date:** 2026-06-17
**Deciders:** Nico Spencer
**Context:** ADR-0001 (Foundations) fixes `genesis_tree` — the `Seed` → `Branch` engine, `TreeContext`, `TreeOwner`, keyed reconcile — as the Flutter-proven build/element machinery minus Flutter, and names its consumers: `genesis_perception` (measurement) and any other domain that mounts on the tree. ADR-0005 names **Attention** as the subscription graph (`Watch`, which per A13 lives in `tree`'s composition layer) and the rebuild path as the `TreeOwner` dirty/flush pipeline (`perceived()` → `markNeedsHarvest` → dirty set → `flushHarvest` are the perception-domain *names* for it). Both leave one discipline implicit: **when does the gathering of observed/source state happen, relative to `build()`?** It surfaced in `lenny-9kni`, which generalized lenny's host so a non-Flutter Dart program is perceived and driven over the same surface as a Flutter app; hosting an async-I/O source (a tmux process) *looked* like it needed an async `build()`. Nico's reframe — *"just have a stateful perception watching the thing it's perceiving"* — dissolved it, and on inspection the rule is not about perception at all: it is a property of the `Seed`/`Branch` substrate, the same property that makes every Flutter `build()` synchronous.

---

## Decision 1 — Every `build()` on the tree is synchronous

A `Seed`'s `build()` — `StatelessSeed.build`, and a `StatefulSeed`'s `State.build` — is a **pure, synchronous read of already-current in-memory state** that returns a child `Seed`. It performs no I/O, no awaiting, no gathering. This is the build model `genesis_tree` inherited wholesale from Flutter's element tree (ADR-0001); it is restated here as a substrate invariant because lenny-9kni proved it is load-bearing *across hosts and domains*, not a Flutter-lineage accident.

It binds **everything that mounts on the tree** — `genesis_perception` measurements, human-facing/expression surfaces, any future domain — exactly as Flutter's synchronous `build()` binds every widget. (the_grid's reactive domain projections are the same shape one layer up, per ADR-0005 Decision 5; whether the grid mounts *on* `genesis_tree` is the still-open A7 and out of scope here.)

The corollary is the rule to state out loud: **`build()` is never async.** A `Future<Seed> build()` is always a design error; the impulse to write one is the signal that the node is missing a watcher (Decision 2).

## Decision 2 — Changing/async sources are watched out-of-band; the watcher feeds a live snapshot

Whatever a node measures or projects — widget state, a provider container, an external process, a persistence store — is tracked by an **out-of-band watcher** that keeps a live in-memory snapshot current; `build()` reads that snapshot synchronously. The watcher is existing tree machinery, not a new mechanism:

- **`Watch`** (the Attention primitive, ADR-0005 Decision 1 / A13) is the substrate-level subscription: a `StatelessSeed` that depends on a watched source rebuilds when it changes, holding no state itself.
- **`StatefulSeed` + `State`** (the `StatefulWidget`/`State` analogue) is the home for a *managed* subscription: `State.initState` opens it, the change callback calls `setState` — driving the `TreeOwner` dirty/flush pipeline (`markNeedsHarvest`/`flushHarvest` in the perception domain) so exactly the target subtree rebuilds — and `State.dispose` tears it down.

The async work — opening a connection, starting a poll loop, attaching a listener — lives in the watcher's setup, **never** in the build path. Change *signals* fold into the snapshot out-of-band; `build()` only ever reads.

## Decision 3 — The litmus: an async-I/O source fits the sync contract with no contract change

The test that the discipline is honored: **a source whose state can only be gathered asynchronously must still fit the synchronous build contract without changing it.** If adding such a source tempts a change to any `build()` signature, the watcher is missing.

`lenny-9kni` is the worked proof — two `genesis_perception` measurements at opposite ends of the latency spectrum, both sync-build, both on the unchanged tree contract:

- **In-memory source — Riverpod.** A `ProviderObserver` watches the container out-of-band; `build()` reads the live observer state. (lenny `RiverpodLeonardExtension`.)
- **Async-I/O source — tmux.** A watcher subscribes to a `genesis_tmux` `PollObservationSource` (or `ControlModeObservationSource`); change events refresh a cached snapshot; `build()` reads it synchronously. The async-I/O target fit the *unchanged* sync contract — the litmus, passed, with no change to `Seed`/`Branch` or the perception domain. (lenny `leonard_tmux.TmuxExtension`.)

## Consequences

- **One substrate, uniform across every domain, host, and audience.** The same synchronous build serves a Flutter binding (measuring widget state) and a pure-Dart VM-service host (measuring an external process), and any domain that mounts on the tree, rendering to every audience on the ADR-0001 rendering axis — without any node, host, or downstream consumer (RPC → deserialize → render) becoming async. A build is always a cheap, deterministic, side-effect-free read.
- **Latency is bounded by the watcher, surfaced honestly.** A snapshot can be momentarily stale (bounded by the watcher's cadence — a poll interval, an event hop); it is never *blocking*. Consumers needing freshness poll the cheap, sync build rather than paying I/O inside a single read.
- **Staleness stays a hit-test concern, not a build hazard.** Because the world is watched, not pulled at build time, "the projection moved under the actor" remains the structured `staleUnmounted` rejection of ADR-0005 Decision 3 — never something a synchronous `build()` must defend against.

## Alternatives considered

- **Async `build()` (`Future<Seed>`)** — let a node gather at build time. Rejected: it leaks the source's I/O latency into the build hot path and forces the whole pipeline and every consumer async, to serve the minority of sources that are async-I/O. The watcher confines async to setup and keeps `build()` pure for everyone.
- **Gather-on-demand at the host/consumer boundary** (an async `observe()` per request) — the shape `leonard_tmux` originally had. Rejected: it makes structurally identical consumers diverge over an accident of the source, and re-derives the snapshot on the read path every time. Watching amortizes it and unifies them.
- **A separate async node/build subtype** for I/O sources — rejected: a second contract to host, route, and reconcile, when `Watch` / `StatefulSeed` already absorb async with no forked build signature.

## Provenance

No prior `ADR-0000` register entry — this discipline surfaced in lenny `lenny-9kni` (2026-06-17) and was promoted directly by Nico, then re-scoped the same session from perception to the `genesis_tree` substrate. The mirrored consumer-side convention lives at `com.nicospencer/lenny/CLAUDE.md` ("Conventions & Patterns → Perception is pull-free"); the precedents in Decision 3 (`RiverpodLeonardExtension`, `leonard_tmux.TmuxExtension`) are lenny extensions on `genesis_perception`. Elaborates ADR-0001 (the `Seed`/`Branch`/`TreeOwner` engine) and reads against ADR-0005 (Attention/`Watch`; the dirty/flush pipeline; `StatefulPerceptionElement`).
