# genesis_typesetting

The cell/terminal render backend (ADR-0004 Decision 2): a pure-Dart,
double-buffered character grid set in minimal ANSI, repainted from the tree's
**real drained dirty set** — `TreeOwner.flush()` returns the branches a pass
rebuilt (ADR-0001 Decision 5), and this package maps them to screen regions
and repaints only those.

This productionizes spikes 2 and 4 from the lenny de-risking campaign, and
**deletes spike 4's documented fake**: there, the owner's dirty set was
private, so dirty-region mapping was faked with a builder-driven
`RepaintNotifier` (each watched box's builder marking its own region). The
flush API now says what rebuilt, so region mapping is a contract, not
builder cooperation. No notifier exists anywhere in this package or its
tests.

## What's here

| Type | Role |
|---|---|
| `Cell`, `CellChange` | one styled cell (rune + 256-color fg/bg + bold, value equality); one diff entry |
| `CellGrid` | double-buffered W×H grid; draw ops (`set`, `putText`, `drawBox` with box-drawing chars + embedded title) target the back buffer; `swap()` diffs, promotes, and returns the minimal change list |
| `AnsiEncoder` | change list → minimal ANSI: `ESC[row;colH` addressing, SGR only on style transitions, horizontal-run batching, one trailing `ESC[0m`. Write-only — no terminal queries, no raw mode, pipe/CI-safe |
| `Rect`, `Region` | integer cell rectangles; a delegate-claimed fixed region (canonical instances, compared by identity) |
| `PaintDelegate` | **the paint seam** (see below) |
| `Typesetter`, `FrameRecord` | the live loop and its per-frame instrumentation |
| `subtreeContains` | ancestry helper over `Branch.visitChildren` for delegates mapping rebuilt branches to containing subtrees |

## The paint-delegate contract

Typesetting owns the surface; **domains own meaning** (ADR-0001 Decision 3).
This package knows no domain node types — the consumer implements
`PaintDelegate`:

```dart
abstract class PaintDelegate {
  /// Once, at mount: walk the root (visitChildren), claim fixed regions.
  List<Region> assignRegions(Branch root);

  /// Map one rebuilt branch (from TreeOwner.flush) to the region whose
  /// content it affects, or null when it affects none.
  Region? regionFor(Branch rebuilt);

  /// Repaint region.rect's content into the grid's back buffer.
  /// Contract: touch only cells inside region.rect.
  void paint(CellGrid grid, Region region);
}
```

The region model is deliberately simple: **fixed rects, assigned once at
mount**. Full layout (measurement, flex, overflow) is explicitly future work.
The double buffer keeps the pipeline honest regardless of delegate
over-painting: repainting an unchanged region diffs to zero cells and zero
bytes.

`Typesetter` wires the loop:

```text
event -> setState -> owner dirty set -> onNeedsFlush (empty->non-empty edge)
      -> scheduleMicrotask -> owner.flush() -> List<Branch> rebuilt
      -> delegate.regionFor each -> delegate.paint(only those regions)
      -> grid.swap() -> AnsiEncoder -> sink
```

Events arriving before the microtask pass coalesce into one flush. Every
pass is recorded as a `FrameRecord` (regions repainted, cells changed, bytes
emitted, **plus the verbatim flush return**) — the instrumentation surface
for tests and ops. The typesetter is write-only: screen setup/teardown
(clear, cursor parking) is the embedder's choice (ADR-0004 Decision 1).

## Per-frame economy (measured by the tests)

Locality suite, 40×12 grid (480 cells), full-redraw baseline 1053 bytes/frame
(same encoder over every cell — apples-to-apples):

```text
5 ticker events + 1 feed event:
  per-frame changed cells = [2, 2, 2, 6, 7, 6]
  per-frame ANSI bytes    = [24, 24, 24, 28, 29, 21]
```

Every update frame is under 1.5% of the grid and under 3% of a full redraw —
identical to the spike-4 record. Demo (`44×12`, full-redraw baseline 1312
bytes/frame): frame 0 paints the scene in 1255 bytes; the 10 scripted update
frames total **268 bytes (0–38 each; the duplicate event costs 0)** vs 13120
for 10 full redraws — **~49× cheaper**, on a tiny scene; locality makes the
ratio scale with scene size, not change size.

Hard-asserted, not observed: one event costs exactly one flush pass; changed
cells are confined to the watched region; zero cells change in static
regions; the static subtree is never rebuilt (build counter pinned at 1,
branch identity preserved); an identical-value event repaints but diffs to 0
cells / 0 bytes; and the repainted regions derive from the verbatim
`owner.flush()` return — asserted both through `FrameRecord.rebuilt` and
against a raw `TreeOwner` with no `Typesetter` in the loop.

## Run

```bash
dart test                                       # property + locality suites
dart run tool/demo.dart --demo                   # real ANSI, live terminal
dart run tool/demo.dart --demo > /tmp/demo.ansi  # pipe-safe, exits 0
dart run tool/print_snapshots.dart              # regenerate test snapshots
```

## Deferred backlog (ADR-0004 open questions — deliberately not implemented)

- **Input handling / raw mode** — this surface is write-only.
- **Resize / terminal-size detection** — fixed W×H; no `ESC[?…` queries by
  design (pipe-safety).
- **CJK / combining-character width** — one rune == one column today.
- **Scroll-region optimizations** (`ESC[S` etc.) — the diff is per-cell;
  scrolling a pane changes every cell in it.
- **Truecolor** (`38;2;r;g;b`) — 256-color only today; trivial extension.
- **Full layout** — fixed rects per delegate; measurement/flex/overflow are
  future work.
