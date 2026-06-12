import 'package:genesis_tree/genesis_tree.dart';

import 'cell_grid.dart';
import 'rect.dart';
import 'render_branch.dart';

/// A titled, bordered region (render vocabulary v1, register A23): draws a
/// box-drawing frame with [title] embedded in the top border and stacks its
/// children's render branches as lines inside the border.
///
/// [children] mix freely: render seeds ([Text], nested [Box]) and
/// composition seeds (Watch/Stateless/perception nodes) that resolve to
/// them — component branches are transparent to the render tree.
class Box extends RenderSeed {
  /// Creates a titled box over [children], optionally [key]ed.
  const Box({
    required this.title,
    this.children = const [],
    this.accent = -1,
    super.key,
  });

  /// The title embedded in the top border (bold; truncated to fit).
  final String title;

  /// The child configurations, reconciled by key identity.
  final List<Seed> children;

  /// 256-color index for the border and title, or -1 for terminal default.
  final int accent;

  @override
  BoxBranch createBranch() => BoxBranch(this);
}

/// Mounted render branch for [Box]: reconciles its children inside its
/// render scope, flows them as lines inside the border, and paints the
/// frame as its artifact response.
class BoxBranch extends RenderBranch {
  /// Creates the branch for [seed].
  BoxBranch(Box super.seed);

  Box get _box => seed as Box;

  List<Branch> _children = const [];

  @override
  void performRebuild() {
    _children = updateChildren(_children, [
      for (final child in _box.children) renderScopeFor(child),
    ]);
    super.performRebuild();
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  /// Border rows plus the flow of the content lines.
  @override
  int get flowHeight {
    var content = 0;
    for (final child in renderChildren) {
      content += child.flowHeight;
    }
    return content + 2;
  }

  /// Layout v1 flow: stacks render children as lines inside the border
  /// (one-cell frame plus one-cell left/right padding).
  @override
  void performLayout() {
    final innerWidth = rect.width >= 4 ? rect.width - 4 : 0;
    var y = rect.top + 1;
    for (final child in renderChildren) {
      child.layout(
        Rect.fromLTWH(rect.left + 2, y, innerWidth, child.flowHeight),
      );
      y += child.flowHeight;
    }
  }

  /// Paints the frame and blanks the interior; children paint their own
  /// lines after this (parent-first paint order).
  @override
  void paint(CellGrid grid) {
    if (rect.isEmpty) return;
    clearRect(grid);
    grid.drawBox(
      rect.left,
      rect.top,
      rect.width,
      rect.height,
      title: _box.title,
      fg: _box.accent,
    );
  }

  @override
  void unmount() {
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}
