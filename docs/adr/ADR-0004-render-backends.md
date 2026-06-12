# ADR-0004 — Render backends: one tree, multiple surfaces; the window is an embedder choice

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A4
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** Register entry A4 (migrated from lenny A3; rescoped + overlap-corrected) fixes the **rendering axis** of A1's two-axis model: what surfaces a mounted `tree` can render to, and what the engine owes them. This ADR is scoped to that axis only — authoring (measurement vs expression) is ADR-0003 A2UI wire format's territory; the engine's base types (`Seed`/`Branch`/`TreeContext`/`TreeOwner`) are ADR-0001 Foundations'. Evidence comes from de-risking spikes 1, 2, and 4 (lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`, all closed, adversarially verified — independent skeptics re-ran each spike fresh and tamper-tested the checks). **The spike artifacts are untracked working-tree state only** — `com.nicospencer/lenny/spikes/RESULTS.md` plus per-spike `NOTES.md` (`spike1_headless_dump/`, `spike2_cell_grid/`, `spike4_tree_terminal/`); they are reference evidence, disposable once genesis lands the real thing, and are quoted here so the numbers survive their disposal.

---

## Decision 1 — One element tree, three render backends; the window is an embedder choice

genesis carries render backends beyond serialization — as sibling packages, never inside `Branch` core, which is artifact-agnostic (ADR-0001): a backend consumes tree structure, the drained-dirty-set flush (decided in ADR-0001), and a **domain-supplied paint delegate** — `Branch` itself never paints and owns no render artifacts. Three backends, each a different cell of the rendering axis, all consuming the **same** mounted element tree:

- **(a) Pure-Dart cell/TUI backend** — character grid → minimal ANSI; bare VM, no Flutter engine, no Skia (Decision 2).
- **(b) Flutter adapter** — the windowed GUI path; the only backend that brings the engine, and it brings the window with it.
- **(c) Headless real Flutter** (`flutter_tester`) — a **conformance oracle only**, never a render path (Decision 3).

A window is a property of the **chosen embedder**, not the framework. The tree does not know whether it is being drawn into a terminal cell grid, a Flutter view, or nothing at all (model-facing serialization, Decision 5) — backends are orthogonal consumers of the same flush.

## Decision 2 — The cell/TUI backend: double-buffered cell diff → minimal ANSI *(spikes 2 + 4)*

The human-facing terminal surface is a pure-Dart double-buffered cell grid with per-frame cell diffing and a minimal ANSI encoder. Both halves are spike-proven:

**The surface (spike 2, `spikes/spike2_cell_grid/`):** a pure-stdlib program (imports only `dart:io`, `dart:math`, `dart:convert`) maintains a W×H styled cell grid (rune + fg/bg 256-color + bold, value equality), draws into a back buffer, and `swap()` diffs back vs front into a `List<CellChange>`. Proven properties: diff **correctness** (replaying the change list onto the old front buffer reproduces the back buffer exactly, 8 randomized rounds, `Random(42)`), diff **minimality** (change count == cells that actually differ; no-op rewrites never appear), **idempotence** (no draws → 0 changes), and a run-batching encoder (`ESC[row;colH` positioning, SGR only on style transitions, one reset per frame). Write-only — no terminal queries, no raw mode, no `dart:ffi` — so it runs under CI/pipes. Measured byte economy at 80×25 (2000 cells): steady-state frames change 16/2000 cells and emit **~59–61 bytes vs ~2982 for a full redraw (~2%)**, with the full-redraw baseline produced by the same encoder over every cell (apples-to-apples); even the initial 151-cell frame beats full redraw 3.6×.

**The live loop (spike 4, `spikes/spike4_tree_terminal/`):** a live perception tree containing `Watch`-driven state renders to spike 2's grid with the full update path proven end-to-end:

```
event -> perceived() -> owner dirty set -> onNeedsHarvest
      -> flushHarvest -> targeted repaint -> minimal ANSI diff
```

Locality is **hard-asserted**, not observed: one stream event costs exactly one flush pass; the resulting cell diff lies entirely inside the watched box's rect and touches **zero cells** in the static box's rect; the static element is never rebuilt (build counter stays at 1 across all events, element identity unchanged). An event whose value renders identically still rebuilds the Watch, but the double-buffer diff dedups it to 0 changed cells / 0 ANSI bytes. Measured at 40×12 (480 cells, full-redraw baseline 1053 bytes/frame): update frames ran 21–29 bytes; the demo's 10 update frames totalled **268 bytes (0–38 each) vs 10530 for 10 full redraws — ~39× cheaper**, on a tiny scene; locality makes the ratio scale with scene size, not change size.

**Consequence:** the cell backend lands as its own package (working name `tree_terminal`). Spike-documented out-of-scope items carry forward as backlog, not blockers: input handling/raw mode, resize/terminal-size detection, CJK/combining-character width, scroll-region optimizations, truecolor.

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

## Decision 5 — Retained render tree is human-facing only; model-facing stays serialize-only

This resolves the apparent tension with lenny ADR 0001 (`com.nicospencer/lenny/docs/adrs/0001-declarative-perception-framework.md`): 0001 rejected a retained render tree *for the model-facing projection* — and that rejection was **correct**, now scoped rather than overturned. JSON needs hierarchy + size (1-D), not geometry; the model-facing cell of the rendering axis remains serialize-only. A render tree with 2-D cell/pixel geometry is required only for **human-facing** backends. Orthogonal backends off one element tree; no contradiction.

**Sleeper win:** measurement (authoring axis) + human-facing (rendering axis) composes to a **read-only live TUI of the Observation** — lenny's inspector, reborn native-terminal, for free once Decisions 2 and 4 land.

## Decision 6 — Overlap with the_grid: vocabulary collision, not duplication

Verbatim from register A4 (note: "ADR-0004"/"ADR-0003" inside the quote are **the_grid's** ADRs — runtime-providers-tmux and the reconciler convergence port — not this document or genesis ADR-0003):

> **Overlap correction (vs the_grid):** grid's tmux runtime (ADR-0004) is process/session *supervision* (owns terminal real estate); a genesis cell backend *draws into* that real estate — complementary, not duplicative. grid's reconciler (ADR-0003) is a *convergence state machine over beads*; genesis's reconciler is the *tree keyed diff* — two reconcilers at two layers. The earlier "overlap" was **vocabulary collision**, which this factoring disambiguates.

This disambiguates vocabulary only. The deeper relationship — whether grid eventually mounts its bead domains as genesis `tree` nodes or keeps structural snapshot-diffing as a separate layer — is register entry **A7, deliberately left open** and not promoted by this document.

---

## Alternatives considered

- **Flutter-only rendering (require the engine for the TUI)** — rejected: the agent↔human projection must run on the bare VM without Skia; spike 2 proves the zero-engine path is viable at ~2% of full-redraw bytes steady-state.
- **Headless `flutter_tester` as the production TUI render path** — rejected: test binding ≠ production embedder, rasterization not covered, and the binding's conveniences (`renderViews.single`, pinned test font) are test-harness affordances. It earns its keep as the oracle that makes the cell backend's layout *provable*.
- **A retained render tree for every projection, model-facing included** — rejected: re-litigates lenny 0001 instead of scoping it; the model-facing cell needs hierarchy + size, not geometry (Decision 5).
- **Builder-driven dirty-region notification as the permanent backend contract** — rejected: that is spike 4's documented fake, kept honest only by the double buffer. The owner knows what rebuilt; the flush API says so (Decision 4).
- **Full redraw per frame (no cell diff)** — rejected on measured byte economy: ~2% steady-state (spike 2) and ~39× cheaper over a 10-frame update run (spike 4), with the gap scaling with scene size.
- **Unifying with grid's tmux runtime or its reconciler** — rejected: supervision vs drawing, convergence-over-beads vs keyed tree diff — two reconcilers at two layers (Decision 6); merging them re-creates the vocabulary collision as an architecture error.

---

## Register provenance

This document promotes **exactly one** ADR-0000 register entry:

- **A4 (2026-06-11) — One tree, multiple render backends; "the window is an embedder choice" — scoped to the rendering axis** → on ratification, flip A4's status to `promoted → ADR-0004`. The register's spike-verdict header finding tagged to A4 — *"`TreeOwner` must expose the drained dirty set to render backends"* — is motivated here as Decision 4, but the engine-API obligation itself is promoted once, via ADR-0001 Foundations Decision 4 (alongside the co-tagged `Branch.visitChildren` finding, A4/A8), so the flush contract has a single deciding site and flipping A4 orphans neither finding.

Not promoted here (do not flip): **A7** (grid snapshot-diff vs genesis keyed reconcile) stays open in the register per Decision 6. Evidence provenance: all cited spike artifacts are untracked working-tree state under `com.nicospencer/lenny/spikes/`.
