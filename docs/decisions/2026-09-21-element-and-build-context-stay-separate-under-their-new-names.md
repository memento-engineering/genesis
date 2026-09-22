---
status: accepted
date: 2026-09-21
decision-makers:
  - "Nico"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: element-and-build-context-stay-separate-under-their-new-names
  surfaces:
    - "packages/tree/**"
  obsoletes: []
  updates:
    - a8-shed-the-element-context-original-sin-seed-branch-tree-na
    - adr-0001-foundations
  obsoleted-by: null
  updated-by: []
  bead: genesis-6oo
  legacy-id: null
---

# The element tree and the build context stay separate under their new names

## Context and Problem Statement

genesis-0p5 renames the mounted node `Branch` to `Element` and the capability handle `TreeContext` to `BuildContext`. A8 (promoted into ADR-0001 Decision 2) chose `Branch`/`TreeContext` deliberately, to shed Flutter's "original sin" in which `Element` implements `BuildContext` and leaks the mounted node through the context. The round's readiness lens held the bead because a rename touching those names looked like a silent reversal of a ratified decision, and the register rule is that a reversal must be explicit.

## Decision Outcome

Nico ruled 2026-09-22 that the ratified substance of A8 / ADR-0001 Decision 2 is the SEPARATION, not the names: the mounted node does not implement the build context, and the context stays a distinct capability handle passed into build. That fork stands unchanged. The names are amended: `Branch` is now `Element` and `TreeContext` is now `BuildContext`; every clause of A8 and ADR-0001 Decision 2 that names `Branch` or `TreeContext` reads with the new names. Adopting Flutter's vocabulary does not adopt Flutter's inheritance: `Element` must never implement `BuildContext`, and a change that makes it so reverses this decision and needs a new entry.

### Consequences

* Good, because the vocabulary now matches the Flutter analogue readers already know, without re-admitting the context-leak class of bug the fork exists to prevent.
* Bad, because the shared names invite exactly the assumption the fork forbids; the entry, not the type names, carries the constraint.

### Confirmation

`Element` has no `implements BuildContext` (or equivalent) clause in `packages/tree`; a test or lint that asserts the two types are unrelated is the durable check.
