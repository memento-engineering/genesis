---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a31-branch-purity-invariant-lazy-dependent-set-decider-nico
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A31"
---
## A31 (2026-06-14) — Branch purity invariant + lazy dependent set  ·  decider: Nico

**Decision (Nico, directed):** codify the **Branch purity invariant** — `Branch` stays exactly identity + keyed reconciliation + dirtiness + one abstract `performRebuild` hook (no build contract), and **refuses** Flutter `Element`-style accretion (no rendering, gestures/pointers, `addPostFrameCallback`-shaped lifecycle callbacks, timers/tickers/listeners on the base). Build / state / effects / scheduling live in composition subclasses (`ComponentBranch`/`State`/`Sprout`) or domains, never on `Branch`. The one Element-bloat category the base carries — **inherited-value propagation** (`dependOnInheritedSeedOfExactType` + the dependent set) — is ratified as a deliberate, bounded port: a structural tree-query, load-bearing (providers + A24 render-parent threading), now with the dependent set **lazily allocated** (`Set<InheritedBranchBase>? _dependencies`, created only when a branch actually depends on an `InheritedSeed`) so the common no-dependency branch pays nothing. The test for any future `Branch` addition: if it is a callback the framework calls back into, it belongs in a subclass.
**Why:** the seed/branch cut's value is that `Branch` never becomes the junction box `Element` is; making the invariant explicit keeps future agents from accreting lifecycle onto the spine. Prompted by a cross-conversation review of `Branch`/`ComponentBranch`; the as-built check found the base clean — the accretion danger (Sprout's `useEffect`, consent's action seam) is correctly confined to subclasses / the element (reinforced by A30).
**Affects:** ADR-0001 Decision 3 (invariant folded in) + CLAUDE.md conventions; `packages/tree/lib/src/branch.dart` (lazy `_dependencies`). Tree 145 / perception 104 green; analyze clean. **Status:** promoted → ADR-0001 D3, 2026-06-14.

