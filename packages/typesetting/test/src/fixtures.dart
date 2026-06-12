// Shared test fixtures: the CONSUMER side of the paint seam.
//
// Typesetting's LIB knows no domain node types (ADR-0001 Decision 3) — so
// the domain here is the REAL one: genesis_perception's `Node`/`Field`
// vocabulary (register A22; dev dependency). A11 is one-directional —
// perception never imports the expression row, but expression-row tests
// consume perception freely. Painting a perception tree in a terminal is
// ADR-0004's sleeper win, so the fixture doubles as that proof.
//
// There is deliberately NO RepaintNotifier here: spike 4's builder-driven
// dirty-region fake is gone. Region mapping comes only from the drained
// flush list (ADR-0001 Decision 5).
import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

/// Static subtree that counts its builds — instrumentation for the
/// "static subtree never rebuilt" assertion.
class CountingStaticBox extends StatelessSeed {
  const CountingStaticBox({required this.onBuild, super.key});

  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild();
    return const Node(
      'static',
      children: [
        Field('mode', 'idle', key: 'mode'),
        Field('uptime', 'n/a', key: 'uptime'),
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
    final nodeElement = _resolveNode(_topChildren[index]);
    if (nodeElement == null) {
      grid.putText(rect.x, rect.y, '<unrenderable>');
      return;
    }
    final node = nodeElement.seed as Node;
    grid.drawBox(rect.x, rect.y, rect.w, rect.h, title: node.name);
    final lines = _contentLines(nodeElement);
    final maxLen = rect.w - 4;
    for (var j = 0; j < lines.length && j < rect.h - 2; j++) {
      var line = lines[j];
      if (line.length > maxLen) line = line.substring(0, maxLen);
      grid.putText(rect.x + 2, rect.y + 1 + j, line);
    }
  }

  /// Unwraps single-child component chains (Watch/Stateless wrappers) down
  /// to the presentational [NodeElement], using only [Branch.visitChildren].
  NodeElement? _resolveNode(Branch branch) {
    var current = branch;
    for (;;) {
      if (current is NodeElement) return current;
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

  /// [Field] leaves under [nodeElement], depth-first, as `name: value` lines.
  List<String> _contentLines(NodeElement nodeElement) {
    final lines = <String>[];
    void visit(Branch branch) {
      final config = branch.seed;
      if (config is Field) {
        lines.add('${config.name}: ${config.value}');
        return;
      }
      branch.visitChildren(visit);
    }

    nodeElement.visitChildren(visit);
    return lines;
  }
}

/// The fixture tree: root [Node] with three boxes — two live (Watch-driven
/// off StreamControllers the caller controls) and one completely static.
/// genesis_perception vocabulary over genesis_tree composition.
///
/// Box layout: 0 = ticker (Watch&lt;int&gt;), 1 = static, 2 = feed
/// (Watch&lt;String&gt;).
class LocalityFixture {
  LocalityFixture() {
    root = Node(
      'root',
      children: [
        Watch<int>(
          ticker.stream,
          (v) {
            tickerBuilds++;
            return Node(
              'ticker',
              children: [
                Field('count', '$v', key: 'count'),
                Field('square', '${v * v}', key: 'square'),
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
            return Node('feed', children: [Field('last', msg, key: 'last')]);
          },
          initialValue: '(none)',
          key: 'feed',
        ),
      ],
    );
  }

  final ticker = StreamController<int>();
  final feed = StreamController<String>();
  late final Node root;

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
