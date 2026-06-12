/// Integer screen rectangle in cell coordinates, origin top-left.
class Rect {
  /// Creates a rectangle at ([x], [y]) spanning [w] columns by [h] rows.
  const Rect(this.x, this.y, this.w, this.h);

  /// Left column (0-based, inclusive).
  final int x;

  /// Top row (0-based, inclusive).
  final int y;

  /// Width in columns.
  final int w;

  /// Height in rows.
  final int h;

  /// Whether the cell at ([cx], [cy]) lies inside this rectangle.
  bool contains(int cx, int cy) =>
      cx >= x && cx < x + w && cy >= y && cy < y + h;

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'Rect(x=$x,y=$y,${w}x$h)';
}
