# ADR-0004 — Render backends: one tree, multiple surfaces; the window is an embedder choice

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A4
*Amended 2026-06-13 — package names promoted from register A16; the cell backend rewritten from a paint-delegate side-car to render-bearing tree vocabulary, promoted from register A23/A24 (built + landed, commit `27b0802`); fixture/demo composition promoted from register A22.*
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** Register entry A4 (migrated from lenny A3; rescoped + overlap-corrected) fixes the **rendering axis** of A1's two-axis model: what surfaces a mounted `tree` can render to, and what the engine owes them. This ADR is scoped to that axis only — authoring (measurement vs expression) is ADR-0003 A2UI wire format's territory; the engine's base types (`Seed`/`Branch`/`TreeContext`/`TreeOwner`) are ADR-0001 Foundations'. The two render backends are named per register A16: the cell/TUI backend is package **`genesis_typesetting`** (the `tree_terminal` working name from A4 is retired); the windowed Flutter backend is package **`genesis_expression`** (the "Flutter adapter" of A4 folds under it). Evidence comes from de-risking spikes 1, 2, and 4 (lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`, all closed, adversarially verified — independent skeptics re-ran each spike fresh and tamper-tested the checks). **The spike artifacts are untracked working-tree state only** — `com.nicospencer/lenny/spikes/RESULTS.md` plus per-spike `NOTES.md` (`spike1_headless_dump/`, `spike2_cell_grid/`, `spike4_tree_terminal/`); they are reference evidence, disposable once genesis lands the real thing, and are quoted here so the numbers survive their disposal. The spikes' fixed-rect paint-delegate shape was a spike convenience: the landed `genesis_typesetting` (commit `27b0802`) translates it into render branches that paint as their artifact response (Decision 2, amended).

---

## Decision 1 — One element tree, three render backends; the window is an embedder choice

*Amended 2026-06-13 — backends named per register A16; the paint-delegate framing replaced by render-bearing tree vocabulary per register A23/A24.*

genesis carries render backends beyond serialization — as sibling packages, never inside `Branch` core, which is artifact-agnostic (ADR-0001). A backend is not a side-car that paints *for* the tree off a domain-supplied delegate; it is **render-bearing tree vocabulary** — render seeds whose branches own geometry and paint as their own artifact response when they rebuild (ADR-0001 Decision 3's RenderObjectElement analog, Decision 2). The engine supplies only structure, identity, keyed reconcile, and the drained-dirty-set flush (decided in ADR-0001); `Branch` core itself never paints and owns no render artifacts. Three backends, each a different cell of the rendering axis, all consuming the **same** mounted element tree:

- **(a) Pure-Dart cell/TUI backend** — package **`genesis_typesetting`**: character grid → minimal ANSI; bare VM, no Flutter engine, no Skia (Decision 2).
- **(b) Windowed Flutter backend** — package **`genesis_expression`** (A4's "Flutter adapter," folded here): the windowed GUI path; the only backend that brings the engine, and it brings the window with it. It follows the same render-seed pattern as `genesis_typesetting`, against real `dart:ui`.
- **(c) Headless real Flutter** (`flutter_tester`) — a **conformance oracle only**, never a render path (Decision 3).

A window is a property of the **chosen embedder**, not the framework. The tree does not know whether it is being drawn into a terminal cell grid, a Flutter view, or nothing at all (model-facing serialization, Decision 5) — backends are orthogonal consumers of the same flush.

## Decision 2 — The cell/TUI backend (`genesis_typesetting`): render-bearing tree vocabulary, not a paint delegate *(spikes 2 + 4; built + landed `27b0802`)*

*Amended 2026-06-13 — rewritten from register A23/A24. The spikes' fixed-rect side-car (a free-standing `Typesetter` driving the tree from outside, calling a domain `PaintDelegate` to map rebuilt branches onto `Region`s) was a spike convenience, not the architecture. It is **deleted**. Typesetting is now render-bearing tree vocabulary: render seeds mount as render branches that own their `Rect` and paint into the cell grid as their artifact response — ADR-0001 Decision 3's "non-component branches define their own artifact response" (the RenderObjectElement analog), taken literally. `PaintDelegate`/`Region`/`Typesetter`/`subtreeContains` are gone; the cell core, encoder, and measured economy survive the rework byte-identical.*

### The architecture — render seeds → render branches that paint

`genesis_typesetting` mirrors Flutter's widget → element → render pipeline, with one collapse:

- **`RenderSeed extends Seed` / `RenderBranch extends Branch`** — Flutter's `RenderObjectElement` **and** `RenderObject` collapsed into one type. A cell grid is a single immediate surface, so there is no separate retained render node to keep: the branch *is* the render object. A `RenderBranch` owns `Rect rect` (parent-assigned), `renderParent`/`renderChildren`, `flowHeight`, and an abstract `paint(CellGrid)`. Its base rebuild hook (`performRebuild`) marks-needs-layout + marks-needs-paint (containers reconcile children first, then super) — ADR-0001 Decisions 3/4's artifact response, made concrete.
- **The vocabulary (v1):** `Stage{width, height, sink, children, onFrame?}` (root surface; grid fixed at mount), `Box{title, children, accent?}` (titled bordered region), `Text(content)` (one glyph-run / name-value line). Flow heights: `Text` = 1, `Box` = 2 + children, `Stage` = its height. This is RenderObject-level vocabulary, not a widget library.
- **Paint contract:** a render branch paints only cells inside its `rect` and repaints the **full** rect deterministically (clear-rect preamble); the double buffer (below) dedups identical repaints to 0 bytes; the paint dirty set drains depth-ordered so a container's blanking precedes its children's content.
- **Geometry — `Rect`, dart:ui-shaped but VM-pure:** `Rect.fromLTWH` in **integer cell-space**, with its API modeled on `dart:ui` naming (`left`/`top`/`width`/`height`, `right`/`bottom`, `contains`, `Rect.zero`) so typesetting geometry reads like Flutter render geometry. It does **not** import `dart:ui`: that library is engine-only and unavailable on the bare VM — which is exactly where this backend must run, the A4 premise (no engine, no Skia). Documented divergences from `dart:ui`: coordinates are `int` cells, and `right`/`bottom` are *exclusive* bounds. `genesis_expression`'s windowed backend uses the real `dart:ui.Rect`; the oracle (Decision 3) bridges the two.

### The binding is tree-resident — `StageBranch` ≅ `RenderView`, `StageBinding` ≅ `PipelineOwner`

The scheduling glue is **not** a free-standing driver; it lives inside the tree as the root render branch:

- **`StageBranch`** is the `RenderView` analog — the root render branch. It creates and owns a **`StageBinding`** (the `PipelineOwner` analog), whose constructor is private so only `StageBranch` can make one. Frame 0 paints synchronously at mount, so **`owner.mountRoot(Stage(...))` is the whole entry shape** — mount the stage on a `TreeOwner` and the surface is populated.
- The binding **asserts-and-claims `TreeOwner.onNeedsFlush` exclusively** at mount: a `Stage` must be the only consumer of that hook. A second observer on one owner would require a multi-listener edge on `TreeOwner` — a future tree request, deliberately not made.
- The frame pass is `onNeedsFlush` (the dirty set's empty → non-empty edge) → `scheduleMicrotask` → `owner.flush()` → flow relayout (if shape changed) → repaint exactly the dirty render branches' rects → `grid.swap()` → `AnsiEncoder` → sink, once per pass. Every pass is recorded as a `FrameRecord` whose `rebuilt` field is the **verbatim** `flush()` return (no side channels), reachable from `StageBranch.frames`; zero-change frames are recorded but never written to the sink.

### Render-parent threading is typesetting's own — `InheritedSeed<RenderParentLink>`

`Branch` exposes no public parent pointer and the tree's component branches do not thread slots, so typesetting realizes the `attachRenderObject` climb with the **one public ancestor protocol the tree ships** — the same `dependOnInheritedSeedOfExactType` machinery providers use (this is its **second structural consumer**, beyond inherited-provider lookup):

- A render container wraps each child seed in an `InheritedSeed<RenderParentLink>` carrying one identity-stable link to its branch (it never notifies). A mounting render branch resolves `dependOnInheritedSeedOfExactType<RenderParentLink>()` (`attachRenderParent()`) and the nearest enclosing render branch adopts it — the `RenderObject.adoptChild` analog.
- Watch/Stateless/Inherited wrappers — and perception's `Node` — between two render branches compose **transparently**, exactly as component widgets do between `RenderObjectWidget`s, including the dynamic case where a component rebuild deep in the tree replaces its render child and the replacement re-attaches with no container reconcile on the call stack. `renderChildren` is derived by a shallow `visitChildren` descent in tree order across any intervening wrappers. Rejected threading shapes: slot-borne (component branches hardcode slot 0) and call-stack threading (fails the dynamic deep-swap case).

### Layout v1 is minimal flow — constraints protocol DEFERRED

The stage stacks its render children top-to-bottom, full-width; a box stacks its render children as lines inside the border; a child reports the rows it occupies (`flowHeight`) and the parent assigns rects top-down. This is **placement, not negotiation** — a constraints-down/sizes-up protocol is explicitly deferred, recorded here rather than implied.

### The cell core and economy — unchanged from the spike lineage

The double-buffered cell grid, the minimal ANSI encoder, and the measured byte economy are ported from spikes 2 and 4 and reproduced byte-identical through the new render-branch architecture. Both halves are spike-proven:

**The surface (spike 2, `spikes/spike2_cell_grid/`):** a pure-stdlib program (imports only `dart:io`, `dart:math`, `dart:convert`) maintains a W×H styled cell grid (rune + fg/bg 256-color + bold, value equality), draws into a back buffer, and `swap()` diffs back vs front into a `List<CellChange>`. Proven properties: diff **correctness** (replaying the change list onto the old front buffer reproduces the back buffer exactly, 8 randomized rounds, `Random(42)`), diff **minimality** (change count == cells that actually differ; no-op rewrites never appear), **idempotence** (no draws → 0 changes), and a run-batching encoder (`ESC[row;colH` positioning, SGR only on style transitions, one reset per frame). Write-only — no terminal queries, no raw mode, no `dart:ffi` — so it runs under CI/pipes. Measured byte economy at 80×25 (2000 cells): steady-state frames change 16/2000 cells and emit **~59–61 bytes vs ~2982 for a full redraw (~2%)**, with the full-redraw baseline produced by the same encoder over every cell (apples-to-apples); even the initial 151-cell frame beats full redraw 3.6×.

**The live loop (spike 4, `spikes/spike4_tree_terminal/`):** a live perception tree containing `Watch`-driven state renders to spike 2's grid with the full update path proven end-to-end:

```
event -> perceived() -> owner dirty set -> onNeedsHarvest
      -> flushHarvest -> targeted repaint -> minimal ANSI diff
```

Locality is **hard-asserted**, not observed: one stream event costs exactly one flush pass; the resulting cell diff lies entirely inside the watched box's rect and touches **zero cells** in the static box's rect; the static element is never rebuilt (build counter stays at 1 across all events, element identity unchanged). An event whose value renders identically still rebuilds the Watch, but the double-buffer diff dedups it to 0 changed cells / 0 ANSI bytes. Measured at 40×12 (480 cells, full-redraw baseline 1053 bytes/frame): update frames ran 21–29 bytes; the demo's 10 update frames totalled **268 bytes (0–38 each) vs 10530 for 10 full redraws — ~39× cheaper**, on a tiny scene; locality makes the ratio scale with scene size, not change size.

*The landed `genesis_typesetting` reproduces this economy through render branches — every locality property above re-asserted, not re-faked: changed cells are confined to the rebuilt render branch's rect, the static subtree is never rebuilt, an identical-value event repaints but diffs to 0 cells / 0 bytes, and `FrameRecord.rebuilt` is the verbatim `owner.flush()` return. The landed demo (44×12) totals **268 update bytes vs 12970 for 10 full redraws — ~48×**, matching the spike record through the new architecture.*

**Consequence:** the cell backend ships as **`genesis_typesetting`** (built + landed, commit `27b0802`; the `tree_terminal` working name is retired per register A16). Spike-documented out-of-scope items carry forward as backlog, not blockers — and are now ledgered in the package README: input handling/raw mode (the surface is write-only), resize/terminal-size detection (grid fixed at mount; no `ESC[?…` queries, for pipe-safety), CJK/combining-character width, scroll-region optimizations, truecolor, and the constraints-down/sizes-up layout protocol (Layout v1 is minimal flow only).

## Decision 3 — Headless real Flutter is a conformance oracle only, never a render path *(spike 1)*

`flutter_tester` runs the **full** Flutter framework to completion in a plain shell — no window, no GUI — with real layout producing concrete geometry. Spike 1's captured dump (`spikes/spike1_headless_dump/output.log`, test at `packages/exploration_flutter/test/spike/headless_render_dump_spike_test.dart`) shows the root render view at `BoxConstraints(w=800.0, h=600.0)` / 3.0 DPR (physical `Size(2400.0, 1800.0)`), a `RenderFlex` positioned at `Offset(0.0, 56.0)` below a laid-out AppBar, and `RenderParagraph` nodes at concrete `Size(199.5, 20.0)` — text actually shaped and measured, readable both via `debugDumpRenderTree()` and programmatic probes (`tester.renderObject` + `localToGlobal`).

Its role is to **prove the cell backend's layout matches Flutter's instead of asserting it** — a conformance suite, not a deployment target. Oracle practicalities, recorded from the spike:

- The root render object on the multi-view test binding is reached via `tester.binding.renderViews.single` — there is no `renderView` getter; it is a test-binding subclass (`_ReusableRenderView`).
- Text metrics are host-renderer dependent; an oracle comparing exact text geometry must **pin the deterministic `FlutterTest` font** (the flutter_test default), which keeps metrics reproducible.
- The **test binding ≠ production embedder** — platform reporting (`debug mode enabled - macos`) is host-derived, and binding semantics differ from a shipped embedder. This is precisely why (c) is an oracle, not a render path.
- **Rasterization/compositing to pixels is not covered** — spike 1 proves layout geometry only. Pixel-level conformance is out of scope for the oracle as decided here.

## Decision 4 — `TreeOwner` flush hands backends the drained dirty set *(engine API decided once, in ADR-0001 Foundations Decision 4)*

The engine-API consequence of Decision 2, with a documented motivating failure: in spike 4, the owner's dirty set was **private** to package:perception, so dirty-region mapping had to be faked — each watched box's builder marked its own box index on a `RepaintNotifier`, a builder-driven stand-in for a render object marking its region dirty. The pipeline stayed honest only because the double buffer guarantees minimal emission at the diff level regardless of over-marking; but region mapping by builder cooperation is not a contract, it is a workaround.

Therefore: a `TreeOwner` flush **hands the backend what rebuilt**. The engine-API obligation itself is decided once — ADR-0001 Foundations Decision 4 — and this document records the rendering-axis requirement and its motivating failure: a render backend must be able to map rebuilt elements to screen regions without instrumenting builders. (The companion traversal finding from the same spikes — `Branch` needs `visitChildren`; spikes walked by concrete element shape — is co-tagged A4/A8 in the register and likewise lands with ADR-0001 Foundations' base-type API, not here.)

*Amended 2026-06-13 (register A24): the landed `genesis_typesetting` realizes this contract directly — the spike's builder-driven `RepaintNotifier` fake is **deleted**; render branches register on the `StageBinding`'s paint dirty set themselves, and `FrameRecord.rebuilt` is the verbatim `owner.flush()` return with no side channel. `visitChildren` (the co-tagged finding) is the descent that derives a render container's `renderChildren` across intervening component wrappers, so the threading in Decision 2 leans on it as promised.*

## Decision 5 — Retained render tree is human-facing only; model-facing stays serialize-only

This resolves the apparent tension with lenny ADR 0001 (`com.nicospencer/lenny/docs/adrs/0001-declarative-perception-framework.md`): 0001 rejected a retained render tree *for the model-facing projection* — and that rejection was **correct**, now scoped rather than overturned. JSON needs hierarchy + size (1-D), not geometry; the model-facing cell of the rendering axis remains serialize-only. A render tree with 2-D cell/pixel geometry is required only for **human-facing** backends. Orthogonal backends off one element tree; no contradiction.

**Sleeper win:** measurement (authoring axis) + human-facing (rendering axis) composes to a **read-only live TUI of the Observation** — lenny's inspector, reborn native-terminal, for free once Decisions 2 and 4 land.

*Amended 2026-06-13 (register A22) — the sleeper win is now literal.* `genesis_typesetting`'s landed demo is a live `genesis_perception` tree typeset in the terminal: a perception `Node`/`Field` maps into `Box`/`Text` render seeds with a Stateless adapter, the way widgets compose `RenderObjectWidget`s. This rests on the **one-directional** reading of ADR-0001's import rule: `perception` never imports the expression row, but expression-row packages' *tests and demos* consume `genesis_perception` freely (dev dependency). Typesetting's **lib** stays domain-free — it knows no domain node types — but its fixtures and demo *extend* the perception garden rather than forking it (the spike's invented `Pane`/`Label`/`Panel`/`Readout` fixture vocabularies were deleted in favor of perception's real `Node`/`Field`). `genesis_tree`'s own test-fixture `Node` is the one necessary exception — it cannot dev-dep on perception without a workspace cycle (perception → tree) — and stands as the canonical non-component-branch example.

## Decision 6 — Overlap with the_grid: vocabulary collision, not duplication

Verbatim from register A4 (note: "ADR-0004"/"ADR-0003" inside the quote are **the_grid's** ADRs — runtime-providers-tmux and the reconciler convergence port — not this document or genesis ADR-0003):

> **Overlap correction (vs the_grid):** grid's tmux runtime (ADR-0004) is process/session *supervision* (owns terminal real estate); a genesis cell backend *draws into* that real estate — complementary, not duplicative. grid's reconciler (ADR-0003) is a *convergence state machine over beads*; genesis's reconciler is the *tree keyed diff* — two reconcilers at two layers. The earlier "overlap" was **vocabulary collision**, which this factoring disambiguates.

This disambiguates vocabulary only. The deeper relationship — whether grid eventually mounts its bead domains as genesis `tree` nodes or keeps structural snapshot-diffing as a separate layer — is register entry **A7, deliberately left open** and not promoted by this document.

---

## Alternatives considered

- **Flutter-only rendering (require the engine for the TUI)** — rejected: the agent↔human projection must run on the bare VM without Skia; spike 2 proves the zero-engine path is viable at ~2% of full-redraw bytes steady-state.
- **Headless `flutter_tester` as the production TUI render path** — rejected: test binding ≠ production embedder, rasterization not covered, and the binding's conveniences (`renderViews.single`, pinned test font) are test-harness affordances. It earns its keep as the oracle that makes the cell backend's layout *provable*.
- **A retained render tree for every projection, model-facing included** — rejected: re-litigates lenny 0001 instead of scoping it; the model-facing cell needs hierarchy + size, not geometry (Decision 5).
- **Builder-driven dirty-region notification as the permanent backend contract** — rejected: that is spike 4's documented fake, kept honest only by the double buffer. The owner knows what rebuilt; the flush API says so (Decision 4). *In the landed surface (register A24) the fake is deleted outright — render branches register on the binding's paint dirty set themselves.*
- **A paint-delegate side-car: a free-standing `Typesetter` driving the tree from outside, mapping rebuilt branches onto domain-supplied `Region`s via a `PaintDelegate`** *(added 2026-06-13, register A23)* — rejected: it re-externalizes the artifact semantics ADR-0001 (A11) places *in branches*. Nico's question — "Isn't `Typesetter` an element/branch? Aren't `Cell`/`Rect`/`CellGrid` part of the seed tree?" — exposed the side-car as the spike's fixed-rect convenience productionized instead of translated. The render-branch architecture (Decision 2) is the translation; `PaintDelegate`/`Region`/`Typesetter`/`subtreeContains` are deleted.
- **Full redraw per frame (no cell diff)** — rejected on measured byte economy: ~2% steady-state (spike 2) and ~39× cheaper over a 10-frame update run (spike 4; ~48× through the landed render-branch surface), with the gap scaling with scene size.
- **Unifying with grid's tmux runtime or its reconciler** — rejected: supervision vs drawing, convergence-over-beads vs keyed tree diff — two reconcilers at two layers (Decision 6); merging them re-creates the vocabulary collision as an architecture error.

---

## Register provenance

This document promotes the original framing entry plus the 2026-06-13 ratified render-branch round:

- **A4 (2026-06-11) — One tree, multiple render backends; "the window is an embedder choice" — scoped to the rendering axis** → on ratification, flip A4's status to `promoted → ADR-0004`. The register's spike-verdict header finding tagged to A4 — *"`TreeOwner` must expose the drained dirty set to render backends"* — is motivated here as Decision 4, but the engine-API obligation itself is promoted once, via ADR-0001 Foundations Decision 4 (alongside the co-tagged `Branch.visitChildren` finding, A4/A8), so the flush contract has a single deciding site and flipping A4 orphans neither finding.
- **A16 (2026-06-12, decider: Nico) — package naming** → the cell/TUI backend's name `genesis_typesetting` and the windowed Flutter backend's name `genesis_expression` (A4's "Flutter adapter" folded under it) are promoted into the Context block and Decision 1; the `tree_terminal` working name is retired. *(A16 as a whole folds primarily into ADR-0001; only the two render-backend names land here.)*
- **A22 (2026-06-12, decider: Nico) — expression-row tests consume `genesis_perception`; no reinvented fixtures** → promoted into Decision 5 as the now-literal sleeper win and the one-directional import reading.
- **A23 (2026-06-12, decider: Nico) — typesetting is a render-branch vocabulary, not a paint delegate** → promoted as the rewrite of Decision 1's backend framing and of Decision 2; the deleted delegate is recorded in Alternatives.
- **A24 (2026-06-12, AI; ratified Nico 2026-06-13) — `genesis_typesetting` as-built render-branch surface (commit `27b0802`)** → promoted as the concrete surface in Decision 2 (`RenderSeed`/`RenderBranch`, `Stage`/`Box`/`Text`, `StageBranch`≅`RenderView`/`StageBinding`≅`PipelineOwner`, `InheritedSeed<RenderParentLink>` threading, `Rect.fromLTWH`, minimal-flow layout v1) and in the Decision 4 amendment.

Superseded/closed in the register, recorded here for trail: **A20** (the deleted paint-delegate as-built surface — `Typesetter`/`PaintDelegate`/`Region`/`subtreeContains`) was closed by Nico 2026-06-13 as superseded by A24; its surviving pieces (cell core, economy record, "barrel does not re-export `genesis_tree`") live on in A24/Decision 2.

Not promoted here (do not flip): **A7** (grid snapshot-diff vs genesis keyed reconcile) stays open in the register per Decision 6. Evidence provenance: the cited spike artifacts are untracked working-tree state under `com.nicospencer/lenny/spikes/`; the landed render-branch surface and its measured economy are at `packages/typesetting/` (verified against `lib/src` + README, commit `27b0802`).
