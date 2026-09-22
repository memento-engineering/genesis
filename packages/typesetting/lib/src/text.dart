import 'cell_grid.dart';
import 'render_element.dart';

/// A single glyph run (render vocabulary v1): one line of
/// [content], e.g. a name-value readout like `count: 3`.
class Text extends RenderComponent {
  /// Creates a one-line glyph run, optionally [key]ed.
  const Text(this.content, {super.key});

  /// The characters to set. Truncated to the laid-out rect's width; one
  /// rune == one column (CJK width is backlog).
  final String content;

  @override
  TextElement createElement() => TextElement(this);
}

/// Mounted render element for [Text]: a render leaf occupying one flow line;
/// its artifact response paints the run into its rect.
class TextElement extends RenderElement {
  /// Creates the element for [component].
  TextElement(Text super.component);

  Text get _text => component as Text;

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

/// Legacy name for [TextElement].
@Deprecated('Use TextElement instead.')
typedef TextBranch = TextElement;
