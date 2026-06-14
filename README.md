# genesis

A framework-agnostic, **bare-VM** `Seed` → `Branch` keyed-reconcile engine —
Flutter's element/reconciliation model extracted to pure Dart — and the layers
built on it: a measurement domain, schema-first codegen, the A2UI v0.9 wire
format, a terminal render backend, and an enforce/reject action substrate.

genesis is positioned as the **substrate and framework-agnostic renderer for the
[A2UI](https://a2ui.org) ecosystem**: it speaks the same v0.9 wire as Google's
`flutter/genui`, but runs with no Flutter / `dart:ui` dependency, so an agent can
author, drive, render, and act on a UI tree on a plain Dart VM.

> **Status: pre-1.0.** The engine and domains are well-tested and ADR-grounded,
> but the composition layer is still **experimental** (see *Stability*) and some
> wire/render surface is deliberately deferred — see
> [`docs/release-scope.md`](docs/release-scope.md).

## Packages

| Package (dir · pub name) | What it is |
|---|---|
| `tree` · `genesis_tree` | the engine — `Seed` (immutable config) → `Branch` (mounted node), `TreeContext` (a *separate* capability handle, never the branch), `TreeOwner` (scheduler), keyed reconcile, and an experimental composition layer (`Stateless`/`Stateful`/`State`, `InheritedSeed`, `Watch`, and `Sprout` — hooks) |
| `perception` · `genesis_perception` | the measurement domain, rebuilt on the tree spine by subclassing |
| `taxonomy` · `genesis_taxonomy` | schema-first node catalog → a Dart factory registry **and** an LLM tool schema (codegen, one source of truth) |
| `dialogue` · `genesis_dialogue` | the A2UI v0.9 wire: the `updateComponents` codec, a receive-side surface that reconciles re-emissions by key, and `action`-message parsing |
| `typesetting` · `genesis_typesetting` | a bare-VM cell/ANSI render backend — render-bearing tree vocabulary (a terminal A2UI renderer Flutter structurally can't offer) |
| `consent` · `genesis_consent` | the enforce/reject action substrate: validates an action by hit-testing the live tree against catalog-declared affordances, enforcing or refusing with a structured, side-effect-free outcome |

The dependency arc: `tree` ← `perception`; `taxonomy` (codegen); `dialogue`
(consumes `taxonomy` + `tree`); `typesetting` (render backend on `tree`);
`consent` (consumes `dialogue` + `taxonomy` + the live tree).

## Build & test

A Dart pub workspace driven by [Melos](https://melos.invertase.dev).

```bash
dart pub global activate melos   # once
dart pub get                     # resolve the workspace
melos run test                   # all package tests
melos run analyze                # dart analyze
melos run format                 # formatting check
```

Pure Dart, no Flutter — everything runs on the bare VM.

## Design model

genesis is built decision-first. Two documents govern it:

- **`docs/adr/ADR-0000-ai-decision-register.md`** — a living register where every
  AI-made API/naming/semantic decision lands as an amendment and stays pending
  until the maintainer promotes or rejects it.
- **`docs/adr/ADR-0001..0005`** — the ratified ADRs: foundations, schema-first
  codegen, the A2UI wire format, render backends, and the projection/action
  substrate.

Read `ADR-0000` and `ADR-0001` before changing anything structural.

## Stability

The `tree` **composition layer** (`Stateless`/`Stateful`/`State`,
`InheritedSeed`, `Watch`, `Sprout`) is marked EXPERIMENTAL and may change before
1.0. The core spine (`Seed`/`Branch`/`TreeContext`/`TreeOwner`/keyed reconcile)
and the measurement domain are stable in shape. Deferred surface and the 1.0
boundary are tracked in [`docs/release-scope.md`](docs/release-scope.md).

## License

[BSD-3-Clause](LICENSE).
