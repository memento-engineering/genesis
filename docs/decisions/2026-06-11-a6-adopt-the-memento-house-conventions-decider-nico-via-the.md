---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a6-adopt-the-memento-house-conventions-decider-nico-via-the
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A6"
---
## A6 (2026-06-11) — Adopt the memento house conventions  ·  decider: Nico, via the_grid

*(dragged from the_grid ADR-0001 D1/D2/D7 — the genesis-applicable subset)*
**Decision:** genesis adopts the shared memento conventions so code reads identically across genesis/lenny/the_grid: Dart pub workspace + melos; **freezed sealed unions** with `json_serializable` codecs and **exhaustive `switch` as house style**; `build_runner` wired into melos (consistent with A2's codegen); the `analysis_options.yaml` lint shape (strict-casts/inference/raw-types, prefer_single_quotes, sort_pub_dependencies, unawaited_futures, avoid_print); **predictable-flutter layering** (Services → Repositories → Interactors/Selectors → View) and its testing discipline (Fakes-not-mocks, state-transition assertions, offline unit tests).
**Not dragged** (domain-specific — stay grid-local): the bd-CLI/Dolt substrate (grid ADR-0001 D4), the convergence reconciler (ADR-0003), domain projections over beads (ADR-0002), the exploration-protocol observability surface (D6).
**Caveat — Riverpod version divergence is now a shared concern:** lenny is on `flutter_riverpod 2.6`, grid on `riverpod 3.0`. genesis's `tree` core is a reconciler **engine** (its own owner/sink, not Riverpod-based), so Riverpod stays a *consumer* choice; any genesis-level reactive helper must pick a lane or stay Riverpod-agnostic.
**Affects:** genesis `pubspec.yaml`/`melos.yaml`/`analysis_options.yaml` when scaffolded; a genesis `CLAUDE.md` (onboarding, grid ADR-0001 D8). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

