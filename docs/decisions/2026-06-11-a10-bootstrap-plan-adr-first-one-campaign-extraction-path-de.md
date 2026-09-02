---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a10-bootstrap-plan-adr-first-one-campaign-extraction-path-de
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A10"
---
## A10 (2026-06-11) — Bootstrap plan: ADR-first, one-campaign extraction, path-dep wiring  ·  decider: Nico

**Decision:** (a) **ADR-first** — ADRs are drafted from this register and ratified by Nico *before* implementation; drafts carry Status: Proposed and only Nico flips them to Accepted (the Rule, applied to bootstrap). (b) **One campaign** — `tree` extraction + perception rebuilt on it + lenny cutover proceed as a single sequence; perception's existing test suite is the conformance gate; no window with two diverging element cores. (c) **Path deps now, git pin at launch** — consumers wire to genesis via sibling-checkout path dependencies during development, switching to git refs/tags at stabilization for the org move + launch.
**Why:** the spike verdict (all five green, adversarially verified) gates the start; perception is small enough (9 src files) to move whole; sibling path deps give the fastest iteration while the `tree` API is hot.
**Affects:** bootstrap phases 0–3; lenny `pubspec.yaml` wiring at cutover; genesis repo scaffolding (workspace + melos + A6 conventions + CLAUDE.md carrying this register's Rule + `bd init`). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

