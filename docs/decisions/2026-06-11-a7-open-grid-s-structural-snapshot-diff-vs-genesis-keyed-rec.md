---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a7-open-grid-s-structural-snapshot-diff-vs-genesis-keyed-rec
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A7"
---
## A7 (2026-06-11) — Open: grid's structural snapshot-diff vs genesis keyed reconcile  ·  AI (flag, not a decision)

**Recorded as an open relationship, not resolved:** the_grid (ADR-0001 D5) detects change by **structural diff of whole snapshots** (`diffSnapshots`) because beads are not a keyed element tree; genesis reconciles by **key/identity** (lenny ADR 0001's core move — "reconcile by identity, not structural diff"). Open question: does grid eventually mount its bead domains as genesis `tree` nodes (inheriting keyed reconcile + the A5 projection mechanism), or keep structural diffing as a separate layer? Recorded so the divergence isn't silently inherited.
**Affects (if resolved):** the_grid ADR-0001 D5 / ADR-0002; whether grid becomes a genesis consumer *in fact* or only in convention. **Status:** closed (Nico, 2026-06-14) — out-of-scope for genesis: whether `the_grid` adopts genesis is the_grid's decision, recorded in the_grid's own ADRs if/when it consumes genesis (a coordinated city-sibling follow-up, not a wall). The reconciler-vocabulary disambiguation already lives in ADR-0001 D1 / ADR-0004 D6.

