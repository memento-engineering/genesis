---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a20-genesis-typesetting-as-built-api-surface-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A20"
---
## A20 (2026-06-12) — `genesis_typesetting` as-built API surface  ·  AI

**Decision (as built, commit `467224a`; 16/16 tests, adversarially verified incl. three tamper probes; spike 4's RepaintNotifier fake deleted — regions come exclusively from the real `TreeOwner.flush()` drained list):**
- **`Typesetter`** — the live loop: `Typesetter({delegate, width, height, sink, onFrame?})`; `mount(Seed) → Branch` paints frame 0; `onNeedsFlush → scheduleMicrotask → owner.flush()` exactly once per pass; `dispose()` idempotent. *Naming note for Nico:* `Typesetter` is an agent-noun at the TYPE level — A16's rule is scoped to package names (precedent: `TreeOwner`/Flutter's `BuildOwner`); flag if the rule should extend to types.
- **`PaintDelegate`** (the A11 seam — typesetting knows no domain node types): `assignRegions(root)` once at mount (fixed rects; full layout explicitly deferred); `regionFor(rebuilt) → Region?`; `paint(grid, region)` touching only cells inside the region. `Region(id, rect)` instances are canonical, compared by identity.
- **`FrameRecord{index, rebuilt, repainted, changes, bytes}`** — `rebuilt` is the **verbatim** `flush()` return, making flush-mapping assertable with zero side channels; zero-change frames are recorded but not written to the sink.
- **Emission policy:** strictly write-only diff payloads; no clear-screen/cursor-park/terminal queries — screen lifecycle is the embedder's choice (ADR-0004).
- **`subtreeContains(root, target)`** exported — the ancestry helper, since `Branch` has no public parent pointer (worked around contractually; a parent pointer is a *possible* future tree request, not made).
- **Barrel does NOT re-export `genesis_tree`** — deliberate divergence from perception's full re-export (A15): typesetting is a sibling render backend, not a domain face of the spine.
- Cell core ported from spike 2 (Cell/CellGrid double buffer/AnsiEncoder with run batching); economy reproduced byte-identical to the spike record (~49× over the demo). **Deferred:** input/raw mode, resize, CJK width, scroll regions (ADR-0004 backlog).
**Affects:** ADR-0004 at promotion; first expression-row consumer of the composition layer (one of the two consumers the A11 freeze rule needs). **Status:** **superseded → closed (Nico 2026-06-13).** Rejected as a standalone record; A24 is the live typesetting surface (`Typesetter`/`PaintDelegate`/`Region`/`subtreeContains` deleted in the render-branch rework). The cell core, economy record, and the barrel-does-not-re-export-tree call survive in A24.

