---
status: accepted
date: 2026-09-10
decision-makers: ["governor"]
consulted: []
informed: []
register:
  spec: 1
  slug: lifecycle-phase-guard-is-public-tree-api
  surfaces:
    - "packages/tree/**"
  obsoletes: []
  updates:
    - a31-branch-purity-invariant-lazy-dependent-set-decider-nico
  obsoleted-by: null
  updated-by: []
  bead: genesis-xwi
---
## (2026-09-10) — The lifecycle phase guard is public tree API · decider: Governor

**Decision:** `TreeLifecyclePhase` and `TreeLifecyclePhaseGuard` are exported
public `genesis_tree` API by deliberate exception. Other branch kinds,
non-branch lifecycle drivers, and test doubles use this one primitive to
enforce inherited-dependency timing from the same definition.

The guard composes explicit `initState`, `didChangeDependencies`, `building`,
and `dispose` scopes with the existing `TreeOwner` flush marker, and names the
absence of either signal as `notInTreePhase`. Registering an inherited
dependency outside every tree phase throws `StateError` in every build mode.
The existing `initState` and `dispose` violations remain debug assertions with
their diagnostics byte-identical.

**Departure:** this updates
`a31-branch-purity-invariant-lazy-dependent-set-decider-nico`, whose extraction
guidance kept the guard package-private. The public exception is limited to the
phase enum and guard. `Branch`, lazy dependent-set ownership,
`markNeedsRebuild`, the scheduler, and flush ordering remain unchanged; no
lifecycle callback or dependent-set state is added to `Branch`.

**Status:** accepted.
