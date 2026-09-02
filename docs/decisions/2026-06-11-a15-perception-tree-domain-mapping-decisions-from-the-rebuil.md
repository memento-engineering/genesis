---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a15-perception-tree-domain-mapping-decisions-from-the-rebuil
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A15"
---
## A15 (2026-06-11) — perception↔tree domain mapping decisions from the rebuild  ·  AI

**Decision (as built, commit `4da3378`; conformance gate 104/104 with deltas ledgered in `docs/CONFORMANCE-DELTA.md`):**
- `Perception extends Seed` keeps **`createElement()`** as the domain factory; `createBranch()` is a one-line bridge.
- **`markNeedsHarvest` is the domain override point**: `markNeedsRebuild()` funnels into it; it super-calls the tree path (no recursion) — provider invalidation flows through the domain name, which is what kept lenny's invalidation tests valid verbatim.
- **`PerceptionContext implements TreeContext`** via a private wrapper over the canonical tree handle (handle layering; inherits throw-after-unmount for free); adds `perceptionId` + `markNeedsHarvest`; documented as the seam where token budget lands.
- **`PerceptionOwner extends TreeOwner`**; `flushHarvest()` now *returns* the rebuilt list (was void in lenny); `scheduleHarvestFor` dropped (nothing called it).
- **The load-bearing call: composition elements are NOT `PerceptionElement`s.** Stateless/Stateful/Inherited perception elements are thin subclasses of the *tree* branches that only upgrade the handle to `PerceptionContext`; `PerceptionElement extends Branch` is reserved for artifact elements (NodeElement, FieldElement, custom measurement leaves) — mirroring Flutter's ComponentElement vs RenderObjectElement split.
- `Node` ported as a Perception with children widened to `List<Seed>` (mixes artifact leaves with composition configs); **`Field(String name, Object? value)`** added — non-generic on purpose (a `Field<T>` would break canUpdate across value-type changes; null is a legal measurement).
- `Watch` **re-exported from tree, not subclassed** (A13); the perception barrel re-exports tree in full — one import surfaces the spine + domain (the practical form of A12's consequence).
- `build(covariant PerceptionContext)` returns `Seed` (widened so builders can return composition seeds).
**Affects:** lenny's future perception consumers; the budget capability lands on `PerceptionContext`. **Status:** promoted → ADR-0001 D6 (perception↔tree mapping, incl. the load-bearing composition-elements call), 2026-06-13 (commit `cc4bf28`).

