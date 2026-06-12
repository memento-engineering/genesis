# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on
this repo.

## Repo position

**genesis is the shared substrate** — the Seed/Branch/keyed-reconcile engine
extracted from Flutter (package `tree`) plus the measurement domain built on
it (package `perception`). It owns the engine; its consumers own their
domains:

- `com.nicospencer/lenny` — the testing harness, via `perception`
- `engineering.memento/the_grid` — the platform SDK

Consumers wire in via sibling-checkout path dependencies during development,
switching to git refs/tags at stabilization (ADR-0001 Decision 8). Design
lineage: lenny ADR 0001 (declarative perception framework), which migrates
here with the code.

| Package (dir · pub name) | Contents |
|---|---|
| `packages/tree` · `genesis_tree` | the engine: `Seed` → `Branch`, `TreeContext` (separate handle), `TreeOwner`, keyed reconcile |
| `packages/perception` · `genesis_perception` | the measurement domain, rebuilt on the tree spine by subclassing |

Naming scheme (register A16): pubspec names carry a `genesis_` prefix so we
never squat generic pub names; directories stay short; **no `Genesis*` type
prefixes** — `Seed`/`Branch`/`Perception` stay unprefixed. Package names are
human faculties/crafts/achievements, never agent-nouns (`typesetting`, not
`etcher`).

## THE REGISTER RULE

From `docs/adr/ADR-0000-ai-decision-register.md` (the AI decision register, a
living document — never Accepted, never closed):

> Any decision made by AI lands in ADR-0000 as an amendment and **stays
> there** until Nico promotes it (into its own ADR, or a named amendment of an
> existing one) or shoots it down. AI must not write its own decisions
> directly into ADR-0001+; those documents record human-ratified decisions
> only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects · **Status:**
pending | promoted → ⟨where⟩ | rejected.

If you (an AI agent) make an API, naming, or semantic call that is not already
covered by a ratified ADR, record it as the next `A<n>` amendment in ADR-0000
with Status: pending. Only Nico flips statuses or edits ADR-0001+.

## Build & test

`dart pub get` at the repo root resolves the whole pub workspace (root
`pubspec.yaml` lists the workspace members; packages use
`resolution: workspace`).

Install Melos once, globally:

```bash
dart pub global activate melos
```

Then, from the repo root:

```bash
dart pub get        # Resolve the workspace
melos run test      # Run all tests (pure-Dart packages today)
melos run analyze   # dart analyze on the workspace
melos run format    # Check formatting (fails if files need changes)
melos run           # List all available scripts
```

Melos config is embedded in the root `pubspec.yaml` (no separate
`melos.yaml`). The `test` script is structured so a `test:flutter` step slots
in beside `test:dart` when Flutter packages join the workspace; today the
workspace is pure Dart.

## Conventions (ADR-0001 Decision 7 — the memento house set)

- **Lints:** the shared `analysis_options.yaml` shape — `strict-casts` /
  `strict-inference` / `strict-raw-types`; `prefer_single_quotes`,
  `sort_pub_dependencies`, `unawaited_futures`, `avoid_print`. Packages
  include the root file; do not fork per-package rules.
- **Types:** freezed sealed unions with `json_serializable` codecs (when
  codegen lands per ADR-0002); **exhaustive `switch` expressions as house
  style**, compiler-checked.
- **API hygiene:** doc comments on all public API; no `print` in lib code.
- **Testing discipline:** Fakes, not mocks; state-transition assertions;
  offline unit tests.
- **Reactive helpers:** Riverpod stays a *consumer* choice — the `tree` core
  is its own owner/sink (ADR-0001 Decision 7 caveat).
- **Terminology (register A21):** never "plugin" in memento.engineering code,
  docs, or names — the seam word is **extension** (e.g. `CatalogExtension`).
  "Plugin" is reserved for third-party artifacts named that way by their own
  ecosystems (e.g. Flutter platform-channel plugins).
- **Fixtures (register A22):** do not invent fixture node vocabularies —
  expression-row tests/demos dev-depend on `genesis_perception` and use
  `Node`/`Field`. A11 is one-directional: perception never imports the
  expression row; the reverse is fine in test code.

## Where things live

- `docs/adr/` — ADR-0000 (the AI decision register) plus the ratified ADRs:
  0001 foundations, 0002 schema-first codegen, 0003 A2UI wire format,
  0004 render backends, 0005 projection/action substrate. Read ADR-0000 and
  ADR-0001 before changing anything structural.
- `docs/evidence/` — durable evidence artifacts (spike results, conformance
  ledgers) backing register entries and ADRs.
