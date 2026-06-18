// Shared test fixtures: domain composition over the render vocabulary.
//
// Typesetting's LIB knows no domain node types — the domain here is the REAL
// one: genesis_perception's `Node`/`Field` vocabulary (register A22; dev
// dependency), mapped into render seeds by a Stateless adapter the way
// widgets compose RenderObjectWidgets (register A23). Typesetting a live
// perception tree is ADR-0004's sleeper win, so the fixture doubles as that
// proof.
import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

/// The A22+A23 adapter: maps a perception [Node] (with [Field] leaves) into
/// a [Box] of `name: value` [Text] lines — domain vocabulary composing
/// render seeds, exactly as widgets compose RenderObjectWidgets.
class NodeBox extends StatelessSeed {
  const NodeBox(this.node, {this.accent = -1, super.key});

  /// The perception subtree to typeset.
  final Node node;

  /// 256-color accent for the box border, or -1 for terminal default.
  final int accent;

  @override
  Seed build(TreeContext context) => Box(
    title: node.name,
    accent: accent,
    children: [
      for (final child in node.children)
        if (child is Field)
          Text('${child.name}: ${child.value}', key: child.key),
    ],
  );
}

/// Static subtree that counts its builds — instrumentation for the
/// "static subtree never rebuilt" assertion.
class CountingStaticBox extends StatelessSeed {
  const CountingStaticBox({required this.onBuild, super.key});

  final void Function() onBuild;

  @override
  Seed build(TreeContext context) {
    onBuild();
    return const NodeBox(
      Node(
        'static',
        children: [
          Field('mode', 'idle', key: ValueKey('mode')),
          Field('uptime', 'n/a', key: ValueKey('uptime')),
        ],
      ),
    );
  }
}

/// The fixture scene: a [Stage] with three boxes — two live (Watch-driven
/// off StreamControllers the caller controls) and one completely static.
/// genesis_perception vocabulary over the typesetting render vocabulary.
///
/// Box order: 0 = ticker (Watch&lt;int&gt;, 4 rows), 1 = static (4 rows),
/// 2 = feed (Watch&lt;String&gt;, 3 rows).
class LocalityFixture {
  LocalityFixture({
    required Sink<List<int>> sink,
    this.width = 40,
    this.height = 12,
  }) {
    stageSeed = Stage(
      width: width,
      height: height,
      sink: sink,
      children: [
        Watch<int>(
          ticker.stream,
          (v) {
            tickerBuilds++;
            return NodeBox(
              Node(
                'ticker',
                children: [
                  Field('count', '$v', key: ValueKey('count')),
                  Field('square', '${v * v}', key: ValueKey('square')),
                ],
              ),
            );
          },
          initialValue: 0,
          key: ValueKey('ticker'),
        ),
        CountingStaticBox(
          onBuild: () => staticBuilds++,
          key: ValueKey('static'),
        ),
        Watch<String>(
          feed.stream,
          (msg) {
            feedBuilds++;
            return NodeBox(
              Node(
                'feed',
                children: [Field('last', msg, key: ValueKey('last'))],
              ),
            );
          },
          initialValue: '(none)',
          key: ValueKey('feed'),
        ),
      ],
    );
  }

  final int width;
  final int height;
  final ticker = StreamController<int>();
  final feed = StreamController<String>();
  late final Stage stageSeed;

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
