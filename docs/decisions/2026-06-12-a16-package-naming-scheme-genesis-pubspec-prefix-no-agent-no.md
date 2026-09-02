---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a16-package-naming-scheme-genesis-pubspec-prefix-no-agent-no
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A16"
---
## A16 (2026-06-12) — Package naming scheme: `genesis_` pubspec prefix; no agent-nouns; names are human faculties/achievements  ·  decider: Nico

**Decision:** (a) **Pubspec package names carry a `genesis_` prefix** (`genesis_tree`, `genesis_perception`, …) so genesis never squats generic pub names — but the prefix lives in the pubspec ONLY: **no `Genesis*` type prefixes**; `Seed`/`Branch`/`Perception` stay unprefixed. Directory names stay short (`packages/tree`); the package name carries the namespace. (b) **No agent-nouns in genesis** (etcher/illuminator/corrector rejected): package names are human faculties, crafts, achievements — `perception`, `expression`, **`typesetting`**. (c) The terminal/cell render backend = **`genesis_typesetting`** (replaces the `tree_terminal` working name from A4/ADR-0004). (d) The Flutter-facing design system = **`genesis_expression`** — expression is what Nico calls the system itself; the implementation name matches. ADR-0004's "Flutter adapter" backend folds into/under it. (e) Floated but NOT decided: `grammar` (codegen), `koine` (A2UI wire), `covenant` (action router) — functional working names (`tree_codegen` etc.) remain in the ADRs/beads until called.
**Why:** avoids pub squatting without polluting the type space; keeps the family register coherent (faculties + language + crafts, no job titles).
**Affects:** pubspecs + imports of the two landed packages (renamed 2026-06-12); ADR-0004's `tree_terminal` working name; future package scaffolds; bead `genesis-6xd` retitled. **Status:** promoted → ADR-0001 D1 (naming scheme) + ADR-0004 (backend names), 2026-06-13 (commit `cc4bf28`).
**Scope clarification (Nico 2026-06-13):** the no-agent-noun rule governs **package names only**. Type-level agent-nouns are fine and follow Flutter precedent — `TreeOwner`/`PerceptionOwner` (≅ `BuildOwner`), `StageBinding` (≅ `PipelineOwner`/binding), `TreeContext` (≅ `BuildContext`). This resolves the type-naming flags raised in A20 (`Typesetter`, now deleted) and A24 (`StageBinding`) — no type renames.

