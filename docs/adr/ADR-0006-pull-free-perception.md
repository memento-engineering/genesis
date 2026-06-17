# ADR-0006 — Perception is pull-free: synchronous build, out-of-band watch

**Status:** Accepted 2026-06-17 (Nico). No prior register entry — surfaced directly in lenny `lenny-9kni` (the pure-Dart VM-service host) and promoted at Nico's direction.
**Date:** 2026-06-17
**Deciders:** Nico Spencer
**Context:** ADR-0001 (Foundations) fixes the measurement authoring role — a perception is a *read-only* projection of live state, built on the `Seed`/`Branch` engine via `Perception`/`PerceptionContext`/`PerceptionOwner`. ADR-0005 (Projection/action substrate) names **Attention** as the subscription graph (`Watch`) and the enforce path as `perceived()` → `markNeedsHarvest` → owner dirty set → `flushHarvest`. This ADR fixes one discipline those two leave implicit: **when does the gathering of observed state happen, relative to `build()`?** The forcing case was `lenny-9kni`, which generalized the host so a non-Flutter Dart program is perceived and driven over the *same* `ext.exploration.*` surface as a Flutter app. Hosting an async-I/O target (a tmux process, observed by shelling `capture-pane`) appeared to demand an **async `build()`** — which would have rippled async through every host RPC and every downstream consumer. Nico's reframe — *"just have a stateful perception watching the session it's perceiving"* — dissolved it: the synchronous build contract was correct all along; only the consumer's mental model (gather-at-build-time) was wrong.

---

## Decision 1 — `build()` is synchronous; observation latency never lives in build

A measurement perception's `build()` (`StatelessPerception.build`, and a `StatefulPerception`'s `State.build`) is a **pure, synchronous read of already-current in-memory state**. It performs no I/O, no awaiting, no gathering. This is not a new constraint — it is the Flutter-proven build model ADR-0001 inherited (`build` returns a `Seed` synchronously) — but it is now load-bearing across hosts and is therefore named explicitly rather than left as an accident of the Flutter lineage.

The corollary is the rule worth stating: **`build()` is never async.** A `Future<Seed> build()` is always a design error; the impulse to write one is the signal that the perception is missing a watcher (Decision 2).

## Decision 2 — The observed source is watched out-of-band; the watcher feeds a live snapshot

Whatever a perception measures — Flutter widget state, a provider container, an external process — is tracked by an **out-of-band watcher** that keeps a live in-memory snapshot current. `build()` then reads that snapshot synchronously. The watcher is genesis-native machinery, not a new mechanism:

- **`Watch`** (the Attention primitive, ADR-0005 Decision 1) is the substrate-level subscription: a `StatelessPerception` that depends on a watched source rebuilds when it changes, with no state of its own.
- **`StatefulPerception` + `PerceptionState`** (the `StatefulWidget`/`State` analogue) is the home for a *managed* subscription: `State.initState` opens it, the change callback calls the `setState`-analogue (`perceived()` → `markNeedsHarvest` → `flushHarvest`, ADR-0005 Decision 4) to schedule exactly the target subtree's rebuild, and `State.dispose` tears it down.

The async work — opening a control connection, starting a poll loop, attaching a listener — lives in the watcher's setup (`initState`, or the host extension's own `async` lifecycle), **never** in the build path. Change *signals* fold into the snapshot out-of-band; `build()` only ever reads.

## Decision 3 — The litmus: an async-I/O source fits the sync contract with no contract change

The test that this discipline is being honored: **a source whose state can only be gathered asynchronously must still fit the synchronous build contract without changing it.** If adding such a source tempts a change to `build()`'s signature, the watcher is missing.

`lenny-9kni` is the worked proof. Two structurally identical perceptions, opposite ends of the latency spectrum, both sync-build:

- **In-memory source — Riverpod.** A `ProviderObserver` watches the container out-of-band; `build()` reads the live observer state. (lenny `RiverpodLeonardExtension`.)
- **Async-I/O source — tmux.** A watcher subscribes to a `genesis_tmux` `PollObservationSource` (or `ControlModeObservationSource`); `TmuxEvent`s refresh a cached snapshot; `build()` reads it synchronously. The async-I/O target fit the unchanged sync contract — the litmus, passed. (lenny `leonard_tmux.TmuxExtension`.)

## Consequences

- **One substrate, uniform across hosts and audiences.** The same synchronous build serves a Flutter binding (measuring widget state) and a pure-Dart VM-service host (measuring an external process), and renders to every audience on the ADR-0001 rendering axis, without any host — or any downstream consumer (host RPC → deserialize → render) — becoming async. Observation stays a cheap, deterministic, side-effect-free read.
- **Latency is bounded by the watcher, surfaced honestly.** A snapshot can be momentarily stale (bounded by the watcher's cadence — a poll interval, an event-delivery hop); it is never *blocking*. Consumers that need freshness poll the (cheap, sync) observation, rather than paying I/O inside a single read.
- **Staleness stays a first-class outcome, not a build hazard.** Because the world is watched rather than pulled at build time, "the projection moved under the actor" remains the structured `staleUnmounted` rejection of ADR-0005 Decision 3 — a hit-test concern, not something a synchronous `build()` has to defend against.

## Alternatives considered

- **Async `build()` (`Future<Seed>`)** — let a perception gather at build time. Rejected: it leaks the source's I/O latency into the observation hot path and forces the entire observe pipeline and every consumer async, to serve the minority of sources that are async-I/O. The watcher confines the async to setup and leaves build pure.
- **Gather-on-demand at the host boundary** (host calls an async `observe()` per request) — the shape `leonard_tmux` originally had. Rejected: it makes two structurally identical hosts diverge over an accident of the source, and re-derives the whole snapshot on the read path every time. Watching amortizes the cost and unifies the hosts.
- **A separate async perception subtype** for I/O sources — rejected: a second contract to host, route, and reconcile, when `Watch` / `StatefulPerception` already absorb async without a forked build signature.

## Provenance

No prior `ADR-0000` register entry — this discipline emerged in lenny `lenny-9kni` (2026-06-17) and was promoted directly by Nico. The mirrored convention lives in the lenny consumer at `com.nicospencer/lenny/CLAUDE.md` ("Conventions & Patterns → Perception is pull-free"); the precedents cited in Decision 3 (`RiverpodLeonardExtension`, `leonard_tmux.TmuxExtension`) are lenny extensions built on `genesis_perception`. Reads against ADR-0001 (measurement axis; `Perception` on `tree`) and ADR-0005 (Attention/`Watch`; the `markNeedsHarvest`/`flushHarvest` pipeline; `StatefulPerceptionElement`).
