// Shared test fixtures: the CONSUMER side of the paint seam.
//
// Typesetting knows no domain node types (ADR-0001 Decision 3), so the
// domain lives here, in the tests: `Pane`/`PaneBranch` is a bare keyed
// multichild container artifact (the same fixture move genesis_tree makes
// with its test-only Node), `Label` is the leaf vocabulary, and
// `BoxDelegate` implements the PaintDelegate contract with the simple fixed
// region model — one full-width box per direct child of the root, stacked
// top to bottom.
//
// There is deliberately NO RepaintNotifier here: spike 4's builder-driven
// dirty-region fake is gone. Region mapping comes only from the drained
// flush list (ADR-0001 Decision 5).
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

/// Bare keyed-multichild container with a display name (test artifact).
class Pane extends Seed {
  const Pane(this.name, {this.children = const [], super.key});
  final String name;
  final List<Seed> children;
  @override
  PaneBranch createBranch() => PaneBranch(this);
}

/// Branch for [Pane]: a non-component branch whose rebuild hook is keyed
/// reconciliation of its children.
class PaneBranch extends Branch {
  PaneBranch(Pane super.seed);

  List<Branch> _children = const [];

  Pane get pane => seed as Pane;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, pane.children);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  void unmount() {
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}

/// Leaf measurement: a `name: value` line (test artifact).
class Label extends Seed {
  const Label(this.name, this.value, {super.key});
  final String name;
  final String value;
  @override
  LabelBranch createBranch() => LabelBranch(this);
}

/// Branch for [Label]; the empty default rebuild hook.
class LabelBranch extends Branch {
  LabelBranch(Label super.seed);
}

/// Static subtree that counts its builds — instrumentation for the
/// "static subtree never rebuilt" assertion.
class CountingStaticBox extends StatelessSeed {
  const CountingStaticBox({required this.onBuild, super.key});

  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild();
    return const Pane(
      'static',
      children: [
        Label('mode', 'idle', key: 'mode'),
        Label('uptime', 'n/a', key: 'uptime'),
      ],
    );
  }
}

/// Fixed-layout [PaintDelegate]: each direct child of the root gets a
/// full-width box of [boxHeight] rows, stacked top to bottom. Region
/// mapping walks DOWN from the canonical top-level branches via
/// [subtreeContains] (no parent pointers, no builder cooperation).
class BoxDelegate extends PaintDelegate {
  BoxDelegate({required this.width, this.boxHeight = 4});

  final int width;
  final int boxHeight;

  final List<Branch> _topChildren = [];
  final List<Region> _regions = [];

  @override
  List<Region> assignRegions(Branch root) {
    _topChildren.clear();
    _regions.clear();
    root.visitChildren(_topChildren.add);
    for (var i = 0; i < _topChildren.length; i++) {
      _regions.add(Region(i, Rect(0, i * boxHeight, width, boxHeight)));
    }
    return List.of(_regions);
  }

  @override
  Region? regionFor(Branch rebuilt) {
    for (var i = 0; i < _topChildren.length; i++) {
      if (subtreeContains(_topChildren[i], rebuilt)) return _regions[i];
    }
    return null;
  }

  @override
  void paint(CellGrid grid, Region region) {
    final index = region.id as int;
    final rect = region.rect;
    for (var y = rect.y; y < rect.y + rect.h; y++) {
      for (var x = rect.x; x < rect.x + rect.w; x++) {
        grid.set(x, y, Cell.blank);
      }
    }
    final paneBranch = _resolvePane(_topChildren[index]);
    if (paneBranch == null) {
      grid.putText(rect.x, rect.y, '<unrenderable>');
      return;
    }
    grid.drawBox(rect.x, rect.y, rect.w, rect.h, title: paneBranch.pane.name);
    final lines = _contentLines(paneBranch);
    final maxLen = rect.w - 4;
    for (var j = 0; j < lines.length && j < rect.h - 2; j++) {
      var line = lines[j];
      if (line.length > maxLen) line = line.substring(0, maxLen);
      grid.putText(rect.x + 2, rect.y + 1 + j, line);
    }
  }

  /// Unwraps single-child component chains (Watch/Stateless wrappers) down
  /// to the presentational [PaneBranch], using only [Branch.visitChildren].
  PaneBranch? _resolvePane(Branch branch) {
    var current = branch;
    for (;;) {
      if (current is PaneBranch) return current;
      Branch? sole;
      var count = 0;
      current.visitChildren((child) {
        sole = child;
        count += 1;
      });
      if (count != 1) return null;
      current = sole!;
    }
  }

  /// Label leaves under [paneBranch], depth-first, as `name: value` lines.
  List<String> _contentLines(PaneBranch paneBranch) {
    final lines = <String>[];
    void visit(Branch branch) {
      final config = branch.seed;
      if (config is Label) {
        lines.add('${config.name}: ${config.value}');
        return;
      }
      branch.visitChildren(visit);
    }

    paneBranch.visitChildren(visit);
    return lines;
  }
}

/// The fixture tree: root [Pane] with three boxes — two live (Watch-driven
/// off StreamControllers the caller controls) and one completely static.
/// Pure genesis_tree composition; no perception dependency.
///
/// Box layout: 0 = ticker (Watch&lt;int&gt;), 1 = static, 2 = feed
/// (Watch&lt;String&gt;).
class LocalityFixture {
  LocalityFixture() {
    root = Pane(
      'root',
      children: [
        Watch<int>(
          ticker.stream,
          (v) {
            tickerBuilds++;
            return Pane(
              'ticker',
              children: [
                Label('count', '$v', key: 'count'),
                Label('square', '${v * v}', key: 'square'),
              ],
            );
          },
          initialValue: 0,
          key: 'ticker',
        ),
        CountingStaticBox(onBuild: () => staticBuilds++, key: 'static'),
        Watch<String>(
          feed.stream,
          (msg) {
            feedBuilds++;
            return Pane('feed', children: [Label('last', msg, key: 'last')]);
          },
          initialValue: '(none)',
          key: 'feed',
        ),
      ],
    );
  }

  final ticker = StreamController<int>();
  final feed = StreamController<String>();
  late final Pane root;

  /// Builder/build call counters (each is 1 after mount).
  int tickerBuilds = 0;
  int staticBuilds = 0;
  int feedBuilds = 0;

  Future<void> dispose() async {
    await ticker.close();
    await feed.close();
  }
}

/// Byte sink fake (Fakes, not mocks): collects every emitted payload.
class RecordingSink implements Sink<List<int>> {
  final List<List<int>> payloads = [];
  bool closed = false;

  int get totalBytes =>
      payloads.fold(0, (sum, payload) => sum + payload.length);

  @override
  void add(List<int> data) {
    payloads.add(data);
  }

  @override
  void close() {
    closed = true;
  }
}
