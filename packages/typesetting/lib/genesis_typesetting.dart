/// The cell/terminal render backend (ADR-0004) as render-bearing tree
/// vocabulary (register A23): render seeds (`Stage`/`Box`/`Text`) mount as
/// render branches that own their `Rect` and paint into the double-buffered
/// `CellGrid` as their artifact response — ADR-0001 Decision 3's
/// RenderObjectElement analog, taken literally. The stage branch is the
/// RenderView analog and owns the scheduling glue: `TreeOwner.flush()` ->
/// flow relayout -> repaint exactly the dirty render branches' rects ->
/// minimal ANSI to the sink.
///
/// The lib knows no domain node types: domains (e.g. perception) compose
/// render seeds the way widgets compose RenderObjectWidgets (A22).
library;

export 'src/ansi_encoder.dart';
export 'src/box.dart';
export 'src/cell.dart';
export 'src/cell_grid.dart';
export 'src/frame_record.dart';
export 'src/rect.dart';
export 'src/render_branch.dart';
export 'src/stage.dart';
export 'src/text.dart';
