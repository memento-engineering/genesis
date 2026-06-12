/// One styled terminal cell: a Unicode code point plus minimal style.
///
/// Styles are 256-color indices (`-1` = terminal default) plus bold. Value
/// equality drives the double-buffer diff: two cells are the same iff rune
/// and style all match, so a no-op rewrite never shows up as a change.
class Cell {
  /// Creates a cell for code point [rune] with optional style.
  const Cell(this.rune, {this.fg = -1, this.bg = -1, this.bold = false});

  /// Unicode code point to render.
  final int rune;

  /// Foreground 256-color index (0..255), or -1 for terminal default.
  final int fg;

  /// Background 256-color index (0..255), or -1 for terminal default.
  final int bg;

  /// Whether the cell renders bold (SGR 1).
  final bool bold;

  /// The default-styled space cell every buffer starts filled with.
  static const Cell blank = Cell(0x20);

  /// Whether [other] carries the same style (fg/bg/bold), ignoring the rune.
  bool sameStyleAs(Cell other) =>
      fg == other.fg && bg == other.bg && bold == other.bold;

  @override
  bool operator ==(Object other) =>
      other is Cell &&
      other.rune == rune &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(rune, fg, bg, bold);

  @override
  String toString() =>
      "Cell('${String.fromCharCode(rune)}', fg=$fg, bg=$bg, bold=$bold)";
}

/// A single cell that differs between the back and front buffer — one entry
/// of the minimal change list returned by `CellGrid.swap`.
class CellChange {
  /// Creates a change record for the cell at ([x], [y]).
  const CellChange(this.x, this.y, this.cell);

  /// Column of the changed cell (0-based).
  final int x;

  /// Row of the changed cell (0-based).
  final int y;

  /// The new cell value (the back-buffer value promoted to front).
  final Cell cell;

  @override
  String toString() => 'CellChange($x,$y,$cell)';
}
