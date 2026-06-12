/// Demo driver: a scripted ~10-frame animation through the real, tree-native
/// architecture (register A23), emitting real ANSI to stdout (pipe-safe:
/// write-only, no terminal queries, no raw mode) with per-frame stats lines
/// on stderr.
///
/// Run on a real terminal to watch the boxes update in place:
///   dart run tool/demo.dart --demo
///
/// This is ADR-0004's sleeper win made literal: a live genesis_perception
/// tree (`Node`/`Field`, register A22) typeset in the terminal — domain
/// vocabulary mapped into render seeds by a Stateless adapter, the way
/// widgets compose RenderObjectWidgets. The entry shape is the whole point:
/// mount a Stage, and painting just happens.
library;

import 'dart:async';
import 'dart:io';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

Future<void> main(List<String> args) async {
  if (!args.contains('--demo')) {
    stderr.writeln('usage: dart run tool/demo.dart --demo');
    exitCode = 2;
    return;
  }

  final ticker = StreamController<int>();
  final feed = StreamController<String>();

  var totalBytes = 0;
  void reportFrame(FrameRecord f) {
    totalBytes += f.bytesEmitted;
    stderr.writeln(
      'typesetting: frame=${f.index} rebuilt=${f.rebuilt.length} '
      'repaintedRects=${f.repainted.length} changedCells=${f.cellsChanged} '
      'ansiBytes=${f.bytesEmitted}',
    );
  }

  // Screen setup is the embedder's choice: clear + home, write-only.
  stdout.write('\x1b[2J\x1b[H');

  // The tree-native entry shape: mount the Stage; frame 0 paints during
  // mountRoot, and every later frame is scheduled by the stage's binding.
  final owner = TreeOwner();
  final stage =
      owner.mountRoot(
            Stage(
              width: 44,
              height: 12,
              sink: stdout,
              onFrame: reportFrame,
              children: [
                Watch<int>(
                  ticker.stream,
                  (v) => NodeBox(
                    Node(
                      'ticker',
                      children: [
                        Field('count', '$v', key: 'count'),
                        Field('square', '${v * v}', key: 'square'),
                      ],
                    ),
                    accent: 2,
                  ),
                  initialValue: 0,
                  key: 'ticker',
                ),
                const StaticAboutBox(key: 'about'),
                Watch<String>(
                  feed.stream,
                  (msg) => NodeBox(
                    Node('feed', children: [Field('last', msg, key: 'last')]),
                    accent: 6,
                  ),
                  initialValue: '(none)',
                  key: 'feed',
                ),
              ],
            ),
          )
          as StageBranch;

  Future<void> step(void Function() fire) async {
    fire();
    // Sleep only — lets the event + flush microtasks run, and animates the
    // scene when watched on a live terminal. Content is fully scripted.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  await step(() => ticker.add(1)); //  1
  await step(() => feed.add('booting')); //  2
  await step(() => ticker.add(2)); //  3
  await step(() => ticker.add(3)); //  4
  await step(() => feed.add('render loop live')); //  5
  await step(() => ticker.add(3)); //  6  duplicate -> zero-byte frame
  await step(() => ticker.add(42)); //  7
  await step(() => feed.add('diffing only')); //  8
  await step(() => ticker.add(137)); //  9
  await step(() => feed.add('done')); // 10

  // Park the cursor below the scene and reset style (embedder teardown).
  stdout.write('\x1b[${stage.grid.height + 1};1H\x1b[0m');
  await stdout.flush();

  final updateFrames = stage.frames.skip(1).toList();
  final updateBytes = updateFrames.fold<int>(
    0,
    (sum, f) => sum + f.bytesEmitted,
  );
  final fullRedraw = stage.encoder.fullRedrawBytes(stage.grid);
  stderr.writeln(
    'typesetting: summary frames=${stage.frames.length} '
    'totalAnsiBytes=$totalBytes updateFrames=${updateFrames.length} '
    'updateAnsiBytes=$updateBytes fullRedrawBytesPerFrame=$fullRedraw',
  );

  owner.dispose();
  await ticker.close();
  await feed.close();
}

/// The A22+A23 adapter: a perception [Node] (with [Field] leaves) rendered
/// as a [Box] of `name: value` [Text] lines.
class NodeBox extends StatelessSeed {
  const NodeBox(this.node, {this.accent = -1, super.key});

  final Node node;
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

/// Static middle box — never rebuilt by any stream event.
class StaticAboutBox extends StatelessSeed {
  const StaticAboutBox({super.key});

  @override
  Seed build(TreeContext context) => const NodeBox(
    Node(
      'about',
      children: [
        Field('package', 'genesis_typesetting', key: 'package'),
        Field('backend', 'render branches -> ANSI', key: 'backend'),
      ],
    ),
    accent: 4,
  );
}
