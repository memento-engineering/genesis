import 'cell_grid.dart';
import 'render_branch.dart';

/// A single glyph run (render vocabulary v1, register A23): one line of
/// [content], e.g. a name-value readout like `count: 3`.
class Text extends RenderSeed {
  /// Creates a one-line glyph run, optionally [key]ed.
  const Text(this.content, {super.key});

  /// The characters to set. Truncated to the laid-out rect's width; one
  /// rune == one column (CJK width is ADR-0004 backlog).
  final String content;

  @override
  TextBranch createBranch() => TextBranch(this);
}

/// Mounted render branch for [Text]: a render leaf occupying one flow line;
/// its artifact response paints the run into its rect.
class TextBranch extends RenderBranch {
  /// Creates the branch for [seed].
  TextBranch(Text super.seed);

  Text get _text => seed as Text;

  @override
  int get flowHeight => 1;

  @override
  void paint(CellGrid grid) {
    if (rect.isEmpty) return;
    clearRect(grid);
    var content = _text.content;
    if (content.length > rect.width) {
      content = content.substring(0, rect.width);
    }
    grid.putText(rect.left, rect.top, content);
  }
}
