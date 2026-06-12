# Spike 2 — bare-VM ANSI cell grid with double-buffered diff

De-risks genesis A4 fork B: a pure-Dart TUI render surface with zero Flutter
engine. **Answer: yes, viable.** A pure-stdlib Dart program (imports only
`dart:io`, `dart:math`, `dart:convert`) maintains a WxH styled cell grid,
double-buffers it, computes a minimal per-frame cell diff, and emits minimal
ANSI.

## What was proven

- **Cell model**: rune + fg/bg (256-color index, -1 = terminal default) + bold,
  with value equality (`lib/cell_grid.dart`).
- **Double buffering**: draw ops (`set`, `putText`, `drawBox` with Unicode
  box-drawing chars and an embedded bold title) target the back buffer;
  `swap()` diffs back vs front, promotes, and returns `List<CellChange>`.
- **Diff correctness**: replaying the emitted change list onto a copy of the
  old front buffer reproduces the back buffer exactly, over 8 randomized
  mutation rounds (`Random(42)`, reproducible).
- **Diff minimality**: change count == number of cells that actually differ;
  no-op rewrites (writing a cell its existing value) do not appear in the diff.
- **Idempotence**: `swap()` with no draws yields 0 changes.
- **Minimal ANSI emission** (`AnsiEncoder`): `ESC[row;colH` positioning,
  256-color SGR, horizontal-run batching (adjacent changed cells on one row
  share a single cursor move), SGR emitted only on style transitions, one
  `ESC[0m` reset at the end. Write-only — no terminal queries, no raw mode,
  no `dart:ffi` — so it runs under CI/pipes.

## Byte economy (measured, 80x25 = 2000 cells)

```
SPIKE2: frame 1: changed 151/2000 cells, emitted 824 bytes vs 2965 full-redraw
SPIKE2: frame 2: changed 16/2000 cells, emitted 61 bytes vs 2982 full-redraw
SPIKE2: frame 3: changed 16/2000 cells, emitted 59 bytes vs 2982 full-redraw
SPIKE2: frame 4: changed 16/2000 cells, emitted 61 bytes vs 2986 full-redraw
```

Steady-state small frames (k=16) cost ~60 bytes, ~2% of a naive full redraw
(baseline produced by the same encoder over every cell, so the comparison is
apples-to-apples). Even the initial large frame (k=151) beats the full redraw
3.6x because untouched blank cells are never emitted.

Demo mode (80x24, three titled boxes, one animated across 10 frames): frame 1
paints the scene in 1228 bytes; each subsequent move-the-box frame is 45
changed cells / ~441 bytes.

## How to re-run

From the repo root (after `dart pub get --directory=spikes/spike2_cell_grid`,
needed once):

```bash
# self-test: PASS/FAIL lines + SPIKE2: stats, non-zero exit on failure
dart run spikes/spike2_cell_grid/bin/demo.dart --self-test

# demo: real ANSI to stdout, pipe-safe; per-frame stats on stderr
dart run spikes/spike2_cell_grid/bin/demo.dart --demo            # in a terminal
dart run spikes/spike2_cell_grid/bin/demo.dart --demo > /tmp/s2.ansi  # piped
```

Note: pub resolves this package nested under the workspace root independently;
no workspace membership was added (root `pubspec.yaml` untouched).

## Caveats / out of scope

- **No input handling** — write-only surface; raw mode / key events are a
  separate spike.
- **No wide-glyph or combining-character awareness** — one rune == one column;
  CJK/emoji would need width tables.
- **No terminal size detection or resize handling** — fixed WxH; no
  `ESC[?…` queries by design (pipe-safety).
- **Diff is per-cell, not per-region** — scrolling a full pane changes every
  cell in it; `ESC[S`/scroll-region optimizations not explored.
- **SGR state is reset per frame** (`ESC[0m` at end); cross-frame SGR carry
  could shave a few more bytes but complicates correctness.
- 256-color only; truecolor (`38;2;r;g;b`) is a trivial extension.
