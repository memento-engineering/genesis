---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a23-typesetting-is-a-render-branch-vocabulary-not-a-paint-de
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A23"
---
## A23 (2026-06-12) — Typesetting is a render-branch vocabulary, not a paint delegate  ·  decider: Nico

**Decision:** `genesis_typesetting` is rebuilt as **render-bearing tree vocabulary**, mirroring Flutter's widget→element→render factoring exactly:
- **Render seeds** — `Stage` (root surface config: dimensions + sink), `Box` (titled bordered region), `Text`-run (glyph line) — are Seeds; their **branches own geometry (rect) and paint into the `CellGrid` as their artifact response in the rebuild hook** (ADR-0001 Decision 3's RenderObjectElement analog, finally taken literally). `PaintDelegate`/`Region` are **deleted**.
- **`Typesetter` becomes tree-resident** — the root render branch / binding glue (`Stage`'s branch ≅ RenderView; the flush-then-paint scheduling ≅ PipelineOwner), not a free-standing side-car driving the tree from outside.
- **Render-tree threading is typesetting's own** (like `RenderObject.parent`): render branches link to their enclosing render parent across intervening component branches (Watch/Stateless wrappers compose transparently, as widgets do); no `Branch` parent-pointer change requested from `tree`.
- **Layout v1 is minimal flow** (stage stacks boxes; boxes stack text lines) — a constraints-down/sizes-up protocol is explicitly deferred, recorded not implied.
- **Geometry stays VM-pure but dart:ui-shaped:** `dart:ui` is engine-only and unavailable on the bare VM (the A4 fork-B premise), so `Rect` stays integer cell-space with its API modeled on `dart:ui` naming; `genesis_expression`'s windowed backend uses real `dart:ui`; the oracle bridges.
- Domains compose render seeds the way widgets compose RenderObjectWidgets — e.g. a perception `Node`/`Field` → `Box`/`Text` adapter in tests/demo (per A22).
**Why:** Nico, 2026-06-12 ("Isn't `Typesetter` an element/branch? Aren't `Cell`/`Rect`/`CellGrid` part of the seed tree?") — the delegate design re-externalized the artifact semantics A11 places *in branches*; the spike's fixed-rect side-car was productionized instead of translated into the architecture the ADRs already describe.
**Affects:** `genesis_typesetting` (rebuilt; cell core/encoder/economy tests survive); A20 (superseded in part); ADR-0004 wording at promotion; `genesis_expression`'s backend follows the same render-seed pattern. **Status:** promoted → ADR-0004 D1/D2 (render-branch vocabulary), 2026-06-13 (commit `cc4bf28`); built + landed `27b0802` (A24 records the surface).

