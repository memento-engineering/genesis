# genesis_typesetting

The cell/terminal render backend as **render-bearing tree vocabulary**: render
seeds mount as render branches that own their `Rect` and paint into a
double-buffered character grid **as their artifact response** — non-component
branches define their own artifact response, taken literally. There is no
side-car driver
and no paint delegate: the stage branch is the render root *and* the
scheduling glue, and painting is what the tree does when it rebuilds.

The factoring mirrors Flutter's widget → element → render pipeline exactly:

| genesis_typesetting | Flutter | What it is |
|---|---|---|
| `RenderSeed` | `RenderObjectWidget` | immutable config for a render-bearing node |
| `RenderBranch` | `RenderObjectElement` + `RenderObject` (collapsed) | mounted node owning geometry (`rect`) and paint; one type, because a cell grid needs no separate retained render node |
| render branch paint-in-rebuild | `RenderObject.paint` via `RenderObjectElement` | `performRebuild` marks needing paint; the same frame pass paints the rect |
| `RenderBranch.renderParent` | `RenderObject.parent` | typesetting's own render-tree threading, linked at mount across intervening component branches |
| `RenderParentLink` + mount-time ancestor walk | `RenderObjectElement._findAncestorRenderObjectElement()` / `attachRenderObject` | how a mounting render branch finds its enclosing render parent |
| `adoptRenderChild` / `dropRenderChild` | `RenderObject.adoptChild` / `dropChild` | parent-pointer + owner propagation + relayout marking |
| `Stage` / `StageBranch` | `RenderView` (+ the root binding) | the root surface; owns dimensions, the byte sink, and the binding |
| `TreeOwner` | `BuildOwner` | dirty set + depth-ordered flush (package `genesis_tree`) |
| `StageBinding` frame pass | `PipelineOwner.flushPaint` (+ the frame scheduler) | `onNeedsFlush` → microtask → `flush()` → relayout → repaint dirty rects → swap → emit |
| `markNeedsPaint` → `StageBinding` dirty set | `RenderObject.markNeedsPaint` → `owner!._nodesNeedingPaint.add(this)` | every render branch registers directly — the grid is a single surface, so the repaint-boundary walk is unnecessary |

## The vocabulary (v1 — RenderObjects, not a widget library)

| Seed | Branch | Role |
|---|---|---|
| `Stage(width, height, sink, children, onFrame?)` | `StageBranch` | root surface; stacks its children's render branches top-to-bottom full-width; owns the `StageBinding` and frame instrumentation |
| `Box(title, children, accent?)` | `BoxBranch` | titled bordered region; stacks its children's render branches as lines inside the border |
| `Text(content)` | `TextBranch` | one glyph run / name-value line |

The cell core underneath is unchanged: `Cell` /
`CellChange` (value equality), `CellGrid` (double buffer; `swap()` returns
the minimal change list), `AnsiEncoder` (`ESC[row;colH` addressing, SGR only
on style transitions, horizontal-run batching, one trailing reset;
write-only, pipe/CI-safe).

## Entry shape — the binding folds into the tree

```dart
final owner = TreeOwner();
owner.mountRoot(Stage(
  width: 80, height: 24, sink: stdout,
  children: [
    Watch<int>(events, (v) => NodeBox(/* perception Node -> Box/Text */)),
    // ...
  ],
));
// frame 0 is painted; from here, painting just happens:
// event -> setState -> owner dirty set -> onNeedsFlush (empty->non-empty
// edge) -> scheduleMicrotask -> owner.flush() -> List<Branch> rebuilt
// -> flow relayout (if shape changed) -> repaint exactly the dirty render
// branches' rects -> grid.swap() -> AnsiEncoder -> sink
```

Every pass is recorded as a `FrameRecord` (the **verbatim** `flush()`
return, repainted rects, cell changes, bytes), reachable from the stage
branch (`StageBranch.frames`) for tests and ops. Zero-change frames are
recorded but never written to the sink. The stage is write-only — screen
setup/teardown (clear, cursor parking) is the embedder's choice.

## Render-parent threading

`Branch` exposes no parent pointer, and the tree's component branches do not
thread slots — so the `attachRenderObject` climb is realized with the one
public ancestor walk the tree ships: render containers wrap each child seed
in an `InheritedSeed<RenderParentLink>` carrying one identity-stable link to
their branch, and a mounting render branch resolves
`dependOnInheritedSeedOfExactType<RenderParentLink>()` and attaches to the
nearest link. Watch/Stateless/Inherited wrappers — and perception's `Node` —
between two render branches compose transparently, exactly as component
widgets do between `RenderObjectWidget`s, including the dynamic case where a
component rebuild deep in the tree replaces its render child and the
replacement re-attaches with no container reconcile on the call stack.

## Geometry: dart:ui-shaped, VM-pure

`Rect` is integer cell-space with its API modeled on `dart:ui` naming
(`Rect.fromLTWH`, `left`/`top`/`width`/`height`, `right`/`bottom`,
`contains`, `Rect.zero`) so typesetting geometry reads like Flutter render
geometry. It does **not** import `dart:ui`: that library is engine-only and
unavailable on the bare Dart VM, which is exactly where this backend must
run (no engine, no Skia). A windowed (Flutter) render backend would use the
real `dart:ui.Rect`; a conformance oracle bridges the two. Divergence:
coordinates are `int` cells and `right`/`bottom` are exclusive bounds.

## Layout v1: minimal flow (constraints protocol DEFERRED)

The stage stacks its render children top-to-bottom, full-width; a box stacks
its render children as lines inside the border (one-cell frame + one-cell
padding). A child reports the rows it occupies (`flowHeight`); the parent
assigns rects top-down (`layout`/`performLayout`). This is **placement, not
negotiation** — a constraints-down/sizes-up protocol is explicitly deferred,
recorded here rather than implied. Relayout is stage-rooted and runs when
anything changed shape; a relayout that moves no rect paints nothing extra,
and one that does repaints the stage so vacated cells are cleared (the
double buffer keeps emission minimal either way).

## Per-frame economy (measured by the tests)

Locality suite, 40×12 grid (480 cells), full-redraw baseline 1049
bytes/frame (same encoder over every cell — apples-to-apples):

```text
5 ticker events + 1 feed event:
  per-frame changed cells = [2, 2, 2, 6, 7, 6]
  per-frame ANSI bytes    = [24, 24, 24, 28, 29, 21]
```

Every update frame is under 1.5% of the grid and under 3% of a full redraw —
identical to the earlier hand-written backend's record, now produced by render
branches instead of a paint delegate. Demo (44×12, full-redraw baseline 1297 bytes/frame):
frame 0 paints the scene in 1236 bytes; the 10 scripted update frames total
**268 bytes (0–38 each; the duplicate event costs 0)** vs 12970 for 10 full
redraws — **~48× cheaper**, on a tiny scene; locality makes the ratio scale
with scene size, not change size.

Hard-asserted, not observed: one event costs exactly one flush pass; changed
cells are confined to the rebuilt render branch's rect; zero cells change in
static boxes' rects; the static subtree is never rebuilt (build counter
pinned at 1, branch identity preserved); an identical-value event repaints
but diffs to 0 cells / 0 bytes; render branches separated by
Watch/Stateless wrappers attach to the right render parent (render-tree
adjacency asserted explicitly); keyed reorder moves the render tree with
branch identity preserved; and `FrameRecord.rebuilt` is the verbatim
`owner.flush()` return — no side channels.

## Domain composition

The lib knows no domain node types. Tests and the demo consume
`genesis_perception` (dev dependency) and map its vocabulary into render
seeds with a Stateless adapter — `Node('ticker', [Field('count', 3), ...])`
→ `Box(title: 'ticker', children: [Text('count: 3'), ...])` — the way
widgets compose `RenderObjectWidget`s. The demo is the sleeper win made
literal: a live perception tree typeset in the terminal.

## Run

```bash
dart test                                        # property + render suites
dart run tool/demo.dart --demo                   # real ANSI, live terminal
dart run tool/demo.dart --demo > /tmp/demo.ansi  # pipe-safe, exits 0
dart run tool/print_snapshots.dart               # regenerate test snapshots
```

## Deferred backlog (deliberately not implemented)

- **Constraints layout** — a constraints-down/sizes-up protocol (and with
  it relayout boundaries, flex, overflow). v1 is minimal flow only.
- **Input handling / raw mode** — this surface is write-only.
- **Resize / terminal-size detection** — fixed W×H; no `ESC[?…` queries by
  design (pipe-safety). A `Stage`'s grid is fixed at mount.
- **CJK / combining-character width** — one rune == one column today.
- **Scroll-region optimizations** (`ESC[S` etc.) — the diff is per-cell;
  scrolling a pane changes every cell in it.
- **Truecolor** (`38;2;r;g;b`) — 256-color only today; trivial extension.
