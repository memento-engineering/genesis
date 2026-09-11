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
| `packages/taxonomy` · `genesis_taxonomy` | schema-first node catalog → a Dart factory registry **and** an LLM tool schema (codegen, one source of truth) |
| `packages/typesetting` · `genesis_typesetting` | a bare-VM cell/ANSI render backend — render-bearing tree vocabulary for a terminal A2UI renderer |
| `packages/dialogue` · `genesis_dialogue` | the A2UI v0.9 wire: the `updateComponents` codec, a receive-side surface that reconciles re-emissions by key, `action`-message parsing |
| `packages/consent` · `genesis_consent` | the enforce/reject action substrate: hit-tests an action against the live tree + catalog affordances, returns a structured outcome |
| `packages/tmux` · `genesis_tmux` | a zero-dependency, injection-safe tmux client for supervising long-lived agent panes (off-spine; depends only on `meta`) |

Plus `apps/console` · `genesis_console` (`publish_to: none`) — the terminal
driver app that renders an A2UI surface to a character grid and drives it from
natural language.

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

The register captures decisions an AI makes **autonomously** — with no human in
the loop (an unattended agent run). If you (an AI agent) make such an API,
naming, or semantic call that is not already covered by a ratified ADR, record
it as the next `A<n>` amendment in ADR-0000 with Status: pending. A decision
reached collaboratively with Nico is already human-ratified: **do not** log it
here, and **never write to ADR-0000 during an interactive session** — just
carry it out. Only Nico flips statuses or edits ADR-0001+.

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

## Publishing

**`docs/publishing.md` is the law** — people consume these packages now. In
short: pre-publish gates (workspace green; the internal-refs scrub over
everything the archive ships — README, CHANGELOG, `lib/` dartdoc, `example/`;
no working docs inside `packages/<p>/`; committed bump + CHANGELOG; clean
`--dry-run`), pre-1.0 version discipline (**breaking → minor bump**, additive/
fix/docs → patch; interface-member additions are breaking), dependency-order
publishing under the `memento.engineering` verified publisher, then tag
`<pub-name>-v<version>` and push.

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
- **Branch purity (ADR-0001 D3, register A31):** `Branch` stays identity +
  keyed reconcile + dirtiness + one abstract rebuild hook. Never add
  render/gesture/`addPostFrameCallback`/timer/listener machinery to `Branch` —
  build, state, effects, and scheduling live in composition subclasses
  (`ComponentBranch`/`State`/`Sprout`) or domains. Inherited-value propagation
  is the one sanctioned base exception (a structural query, lazily allocated).
  The seam word from spike 5 holds: actions live on the element, not in `tree`.

## Where things live

- `docs/adr/` — ADR-0000 (the AI decision register) plus the ratified ADRs:
  0001 foundations, 0002 schema-first codegen, 0003 A2UI wire format,
  0004 render backends, 0005 projection/action substrate, 0006 pull-free build.
  Read ADR-0000 and ADR-0001 before changing anything structural.
- `packages/` — the seven published members (`tree`, `perception`, `taxonomy`,
  `typesetting`, `dialogue`, `consent`, `tmux`); `apps/` holds the `console`
  driver app (`genesis_console`, `publish_to: none`).
- `docs/evidence/` — durable evidence artifacts (spike results, conformance
  ledgers) backing register entries and ADRs.
