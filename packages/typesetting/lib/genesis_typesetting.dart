/// The cell/terminal render backend (ADR-0004): double-buffered cell grid,
/// minimal ANSI emission, repaint driven by `TreeOwner.flush()` — the real
/// drained dirty set (ADR-0001 Decision 5).
///
/// Typesetting owns the surface; domains own meaning (ADR-0001 Decision 3):
/// the consumer implements [PaintDelegate] to assign regions and paint
/// cells, so this package knows no domain node types.
library;

export 'src/ansi_encoder.dart';
export 'src/cell.dart';
export 'src/cell_grid.dart';
export 'src/paint_delegate.dart';
export 'src/rect.dart';
export 'src/typesetter.dart';
