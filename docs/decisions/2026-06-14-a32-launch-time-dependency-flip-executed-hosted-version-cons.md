---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a32-launch-time-dependency-flip-executed-hosted-version-cons
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A32"
---
## A32 (2026-06-14) — Launch-time dependency flip executed; hosted version constraints, not git refs  ·  decider: Nico (flip); AI (version-vs-git realization)

**Decision:** ADR-0001 Decision 8's "git pin at launch" was executed (Nico-directed) — `publish_to: none` dropped from the six **member** packages (the root `genesis_workspace` pubspec keeps it), and the inter-package deps pinned from `any` to **hosted version constraints `^0.1.0`** (not git refs). Git refs/tags (D8's literal wording) **cannot be published to pub.dev** — a published package's dependencies must be hosted — so for genesis's *own* inter-package deps the correct realization of D8 is hosted version constraints; git refs/tags remain the right tool for **external** consumers (lenny / the_grid) wiring to genesis from their own repos. `resolution: workspace` stays so the monorepo still resolves members locally during dev (`^0.1.0` is satisfied by the local `0.1.0`). `dart pub publish --dry-run` on `genesis_tree` validates — only the standing README/CHANGELOG warnings remain.
**Why:** D8 fixed *that* the loose dev wiring is replaced at launch; the medium (git vs hosted) follows the publish target, and pub.dev requires hosted.
**Affects:** the six member pubspecs; `docs/release-scope.md` (checklist updated). Publishing must proceed in dependency order: `genesis_tree` → `genesis_perception` + `genesis_taxonomy` → `genesis_typesetting` + `genesis_dialogue` → `genesis_consent`. **Status:** pending (clarifies ADR-0001 D8's "git refs" wording for the pub.dev case).

