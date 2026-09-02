---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a11-layering-tree-owns-structure-composition-artifact-semant
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A11"
---
## A11 (2026-06-11) — Layering: `tree` owns structure + composition; artifact semantics are domain-owned  ·  decider: Nico

**Decision:** `Branch` core is **artifact-agnostic** — identity, lifecycle, keyed reconcile, dirtiness, and one abstract rebuild hook (`performRebuild` analog); it carries NO build contract. A thin **composition layer** inside `tree` (ComponentBranch analog: build → child `Seed`s; `Stateless`/`Stateful` + `State` with the neutral setState-analogue; `Inherited`) defines hook = re-run build, and ships **experimental under the two-consumer rule** — its API freezes only after `perception` AND one expression surface both consume it. All artifact/meaning semantics live in domains: harvest/Observation/Digest/**token budget** (== constraints — Flutter's *render*-tree concern, never Element's) belong to `perception` outright; wire/actions/terminal are sibling expression-row packages `perception` never imports.
**Why:** mirrors Flutter's own factoring (Element vs ComponentElement vs RenderObjectElement — two artifact semantics under one tree, base class agnostic to both); answers the "overloading genesis" worry structurally rather than by discipline. From the 2026-06-11 ratification discussion ("genesis is a seed/branch tree, full-stop").
**Affects:** ADR-0001 Decisions 2–4 (reworked at ratification); `tree` package layout; A9's wording (reworded above). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

