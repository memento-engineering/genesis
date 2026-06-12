/// Integer screen rectangle in cell coordinates, origin top-left.
///
/// The API is modeled on `dart:ui`'s `Rect` ([Rect.fromLTWH], [left]/[top]/
/// [width]/[height], [right]/[bottom], [contains], [Rect.zero]) so that
/// typesetting geometry reads like Flutter render geometry (register A23) —
/// but it deliberately does NOT import `dart:ui`: that library is part of the
/// Flutter engine and is unavailable on the bare Dart VM, which is exactly
/// where this backend must run (ADR-0004 Decision 2 — no engine, no Skia).
/// `genesis_expression`'s windowed backend uses the real `dart:ui.Rect`; the
/// conformance oracle (ADR-0004 Decision 3) bridges the two.
///
/// Divergences forced by integer cell space: coordinates are `int` cells, not
/// `double` logical pixels, and [right]/[bottom] are exclusive bounds
/// (`left + width`, `top + height`) — the first column/row NOT covered, which
/// matches `dart:ui`'s left-inclusive/right-exclusive [contains] semantics.
class Rect {
  /// Creates a rectangle at ([left], [top]) spanning [width] columns by
  /// [height] rows — the `dart:ui` `Rect.fromLTWH` shape, in cells.
  const Rect.fromLTWH(this.left, this.top, this.width, this.height);

  /// The empty rectangle at the origin.
  static const Rect zero = Rect.fromLTWH(0, 0, 0, 0);

  /// Left column (0-based, inclusive).
  final int left;

  /// Top row (0-based, inclusive).
  final int top;

  /// Width in columns.
  final int width;

  /// Height in rows.
  final int height;

  /// The first column to the right of this rectangle (exclusive bound).
  int get right => left + width;

  /// The first row below this rectangle (exclusive bound).
  int get bottom => top + height;

  /// Whether this rectangle covers no cells.
  bool get isEmpty => width <= 0 || height <= 0;

  /// Whether the cell at ([x], [y]) lies inside this rectangle
  /// (left/top inclusive, right/bottom exclusive — `dart:ui` semantics).
  bool contains(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'Rect.fromLTWH($left, $top, $width, $height)';
}
