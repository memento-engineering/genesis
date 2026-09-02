---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a24-genesis-typesetting-as-built-render-branch-surface-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A24"
---
## A24 (2026-06-12) — `genesis_typesetting` as-built render-branch surface  ·  AI

**Decision (as built, commit `27b0802`; 25/25 tests, adversarially verified — all three tamper probes tripped; supersedes A20's deleted pieces):**
- **`RenderSeed extends Seed` / `RenderBranch extends Branch`** — Flutter's RenderObjectElement + RenderObject **collapsed into one type** (a cell grid needs no separate retained render node). `RenderBranch` owns `Rect rect` (parent-assigned), `renderParent`/`renderChildren`, `flowHeight`, abstract `paint(CellGrid)`. Base `performRebuild()` = markNeedsLayout + markNeedsPaint (containers reconcile children first, then super) — the artifact response of ADR-0001 D3/D4 taken literally.
- **Paint contract:** paint touches only cells inside `rect` and repaints the FULL rect deterministically (clearRect preamble); the double buffer dedups identical repaints to 0 bytes; the paint dirty set drains depth-ordered so container blanking precedes child content.
- **Render-parent threading:** mount-time ancestor walk via the tree's one public ancestor protocol — render containers wrap child seeds in `InheritedSeed<RenderParentLink>` (identity-stable, never notifies); `attachRenderParent()` resolves it and the parent adopts (the `attachRenderObject`/`RenderObject.adoptChild` analog). Handles the dynamic deep-swap re-attach case. Rejected: slot-borne (ComponentBranch hardcodes slot 0) and call-stack threading (fails the dynamic case). **Keeper note: `dependOnInheritedSeedOfExactType` now has a second structural consumer beyond providers.** `renderChildren` is derived by shallow visitChildren descent (tree order across any wrappers — perception's `Node` composes transparently for free).
- **Vocabulary v1:** `Stage{width, height, sink, children, onFrame?}` (root; grid fixed at mount), `Box{title, children, accent}`, `Text(content)`. Flow heights: Text=1, Box=2+children, Stage=its height.
- **Binding is tree-resident:** `StageBinding` (PipelineOwner analog) has a private constructor — only `StageBranch` (RenderView analog) creates it; frame 0 paints synchronously at mount, so `owner.mountRoot(Stage(...))` is the whole entry shape. **It asserts-and-claims `owner.onNeedsFlush` exclusively** — a second observer on one owner would need a multi-listener edge on `TreeOwner` (future tree request, not made).
- **`Rect.fromLTWH`** integer cell-space, dart:ui-shaped names, **exclusive int right/bottom** (documented divergence from dart:ui's doubles); engine-only constraint documented in-source.
- **Deleted:** `Typesetter`, `PaintDelegate`, `Region`, `subtreeContains` (obsoleted by renderParent/renderChildren). Barrel still does not re-export `genesis_tree` (A20 call carried forward).
- **A18 interaction (resolved 2026-06-13):** the A9 no-fast-path cascade makes a `Box` update repaint its `Text` children every time — locality holds at the box rect and the buffer dedups. A18 is now **ratified to port** (`genesis-4m1`); once it lands, the `identical()` skip shrinks the dirty-paint set further (const `Text` children under an unchanged `Box` stop repainting). Economy through the new architecture reproduced the spike record exactly (268 update bytes vs ~12,970 full redraws, ~48×).
**Affects:** ADR-0004 at promotion; the `genesis_expression` backend pattern; A18's cost/benefit ledger. **Status:** promoted → ADR-0004 D2/D4 (as-built render-branch surface), 2026-06-13 (commit `cc4bf28`).

