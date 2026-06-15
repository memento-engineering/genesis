import 'cell.dart';

/// Double-buffered W x H cell grid.
///
/// Draw ops ([set], [putText], [drawBox], [clear]) target the back buffer;
/// [swap] diffs back vs front, promotes the back buffer to front, and
/// returns the minimal change list — exactly the cells that differ, no
/// no-op rewrites. The back buffer keeps its contents across frames, so each
/// frame draws incrementally on top of the current scene (or calls [clear]
/// first to redraw from blank).
class CellGrid {
  /// Creates a [width] x [height] grid with both buffers blank.
  CellGrid(this.width, this.height)
    : _front = List<Cell>.filled(width * height, Cell.blank),
      _back = List<Cell>.filled(width * height, Cell.blank);

  /// Grid width in columns.
  final int width;

  /// Grid height in rows.
  final int height;

  final List<Cell> _front;
  final List<Cell> _back;

  /// Total number of cells (`width * height`).
  int get cellCount => width * height;

  /// The front-buffer (last-emitted) cell at ([x], [y]).
  Cell frontAt(int x, int y) => _front[y * width + x];

  /// The back-buffer (being-drawn) cell at ([x], [y]).
  Cell backAt(int x, int y) => _back[y * width + x];

  /// Snapshot of the current front buffer (row-major copy).
  List<Cell> frontSnapshot() => List<Cell>.of(_front);

  bool _inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  /// Sets one cell in the back buffer; silently clips out-of-bounds writes.
  void set(int x, int y, Cell cell) {
    if (_inBounds(x, y)) _back[y * width + x] = cell;
  }

  /// Fills the entire back buffer with [fill].
  void clear([Cell fill = Cell.blank]) {
    for (var i = 0; i < _back.length; i++) {
      _back[i] = fill;
    }
  }

  /// Writes [text] into the back buffer starting at ([x], [y]); clips at
  /// grid edges. One rune == one column (no wide-glyph awareness — deferred
  /// to the backlog).
  void putText(
    int x,
    int y,
    String text, {
    int fg = -1,
    int bg = -1,
    bool bold = false,
  }) {
    var cx = x;
    for (final rune in text.runes) {
      set(cx, y, Cell(rune, fg: fg, bg: bg, bold: bold));
      cx++;
    }
  }

  /// Draws a box outline with Unicode box-drawing characters and an optional
  /// bold [title] embedded in the top border. When [fillInterior] is true the
  /// interior is filled with styled blanks. Boxes smaller than 2x2 are
  /// ignored; titles need a width above 5 and are truncated to fit.
  void drawBox(
    int x,
    int y,
    int w,
    int h, {
    String? title,
    int fg = -1,
    int bg = -1,
    bool bold = false,
    bool fillInterior = false,
  }) {
    if (w < 2 || h < 2) return;
    Cell c(int rune) => Cell(rune, fg: fg, bg: bg, bold: bold);
    const tl = 0x250C, tr = 0x2510, bl = 0x2514, br = 0x2518; // ┌ ┐ └ ┘
    const hbar = 0x2500, vbar = 0x2502; // ─ │
    set(x, y, c(tl));
    set(x + w - 1, y, c(tr));
    set(x, y + h - 1, c(bl));
    set(x + w - 1, y + h - 1, c(br));
    for (var i = 1; i < w - 1; i++) {
      set(x + i, y, c(hbar));
      set(x + i, y + h - 1, c(hbar));
    }
    for (var j = 1; j < h - 1; j++) {
      set(x, y + j, c(vbar));
      set(x + w - 1, y + j, c(vbar));
      if (fillInterior) {
        for (var i = 1; i < w - 1; i++) {
          set(x + i, y + j, Cell(0x20, fg: fg, bg: bg));
        }
      }
    }
    if (title != null && w > 5) {
      final maxLen = w - 5;
      final t = title.length > maxLen ? title.substring(0, maxLen) : title;
      putText(x + 2, y, ' $t ', fg: fg, bg: bg, bold: true);
    }
  }

  /// Diffs back vs front, promotes the back buffer to front, and returns the
  /// minimal change list (exactly the cells that differ, in row-major order).
  List<CellChange> swap() {
    final changes = <CellChange>[];
    for (var i = 0; i < _back.length; i++) {
      if (_back[i] != _front[i]) {
        changes.add(CellChange(i % width, i ~/ width, _back[i]));
        _front[i] = _back[i];
      }
    }
    return changes;
  }

  /// Renders the front buffer to a multi-line string — runes only, styles
  /// dropped, trailing spaces trimmed per row. The snapshot format used by
  /// the tests.
  String frontToString() {
    final rows = <String>[];
    for (var y = 0; y < height; y++) {
      final sb = StringBuffer();
      for (var x = 0; x < width; x++) {
        sb.writeCharCode(frontAt(x, y).rune);
      }
      rows.add(sb.toString().replaceFirst(RegExp(r' +$'), ''));
    }
    return rows.join('\n');
  }
}
