/// The locality suite against the real, tree-resident live loop (register
/// A23): stream event -> dirty set -> onNeedsFlush -> microtask frame pass
/// -> owner.flush() -> flow relayout -> repaint exactly the dirty render
/// branches' rects -> double-buffered diff -> minimal ANSI.
///
/// There is no side-car driver and no paint delegate: the render branches
/// paint as their artifact response, and the FrameRecord carries the
/// verbatim flush return.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';
import 'src/snapshots.dart';

/// Whether [inner] lies entirely inside [outer].
bool rectWithin(Rect inner, Rect outer) =>
    inner.left >= outer.left &&
    inner.right <= outer.right &&
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom;

/// The sole child of [branch], via the public traversal contract.
Branch innerOf(Branch branch) {
  late Branch inner;
  var count = 0;
  branch.visitChildren((child) {
    inner = child;
    count++;
  });
  expect(count, 1, reason: 'expected exactly one child under $branch');
  return inner;
}

void main() {
  group('Stage live loop', () {
    late LocalityFixture fx;
    late RecordingSink sink;
    late TreeOwner owner;
    late StageBranch stage;

    setUp(() {
      sink = RecordingSink();
      fx = LocalityFixture(sink: sink);
      owner = TreeOwner();
      stage = owner.mountRoot(fx.stageSeed) as StageBranch;
    });

    tearDown(() async {
      owner.dispose();
      await fx.dispose();
    });

    /// The top-level render boxes, in render-tree (flow) order:
    /// 0 = ticker, 1 = static, 2 = feed.
    List<RenderBranch> boxes() => stage.renderChildren;

    test('mounting the stage paints frame 0 — painting just happens', () {
      expect(stage.frames, hasLength(1));
      expect(stage.flushCount, 0, reason: 'frame 0 is a paint, not a flush');
      final f0 = stage.frames[0];
      expect(f0.rebuilt, isEmpty, reason: 'nothing flushed at mount');
      expect(
        f0.repainted,
        contains(stage.rect),
        reason: 'frame 0 repaints the whole stage',
      );
      expect(f0.changes, isNotEmpty);
      expect(f0.bytes, isNotEmpty);
      expect(sink.payloads, hasLength(1));
      expect(stage.grid.frontToString().trimRight(), initialSnapshot);
    });

    test('flow layout v1: boxes stacked top-to-bottom full-width; text '
        'lines inside the border', () {
      expect(boxes(), hasLength(3));
      expect(boxes()[0].rect, const Rect.fromLTWH(0, 0, 40, 4));
      expect(boxes()[1].rect, const Rect.fromLTWH(0, 4, 40, 4));
      expect(boxes()[2].rect, const Rect.fromLTWH(0, 8, 40, 3));
      final tickerLines = boxes()[0].renderChildren;
      expect(tickerLines, hasLength(2));
      expect(tickerLines[0].rect, const Rect.fromLTWH(2, 1, 36, 1));
      expect(tickerLines[1].rect, const Rect.fromLTWH(2, 2, 36, 1));
      expect(stage.rect, const Rect.fromLTWH(0, 0, 40, 12));
    });

    test('one stream event -> exactly one flush pass; changed cells '
        'confined to the rebuilt render branch\'s rect (LOCALITY)', () async {
      fx.ticker.add(7);
      await pumpEventQueue();

      expect(stage.flushCount, 1, reason: 'one event must cost one flush pass');
      expect(stage.frames, hasLength(2));
      final f = stage.frames[1];
      final tickerRect = boxes()[0].rect;
      final staticRect = boxes()[1].rect;
      final feedRect = boxes()[2].rect;

      expect(f.repainted, isNotEmpty);
      for (final r in f.repainted) {
        expect(
          rectWithin(r, tickerRect),
          isTrue,
          reason: 'repainted rect $r escaped the ticker box $tickerRect',
        );
      }
      expect(f.changes, isNotEmpty);
      for (final c in f.changes) {
        expect(
          tickerRect.contains(c.x, c.y),
          isTrue,
          reason: '$c escaped the rebuilt render branch\'s rect $tickerRect',
        );
      }
      expect(
        f.changes.where((c) => staticRect.contains(c.x, c.y)),
        isEmpty,
        reason: 'zero cells may change inside the static box',
      );
      expect(
        f.changes.where((c) => feedRect.contains(c.x, c.y)),
        isEmpty,
        reason: 'zero cells may change inside the other live box',
      );

      // Economy: the diff frame must be far cheaper than a full redraw.
      final fullRedraw = stage.encoder.fullRedrawBytes(stage.grid);
      expect(
        f.bytesEmitted,
        lessThan(fullRedraw ~/ 10),
        reason: 'diff bytes ${f.bytesEmitted} vs full redraw $fullRedraw',
      );
    });

    test('identical-value event -> repaint happens but 0 cells diff '
        '(double-buffer dedup)', () async {
      fx.ticker.add(7);
      await pumpEventQueue();
      final framesBefore = stage.frames.length;
      final buildsBefore = fx.tickerBuilds;
      final payloadsBefore = sink.payloads.length;

      fx.ticker.add(7); // same value: rebuild happens, pixels identical
      await pumpEventQueue();

      expect(
        fx.tickerBuilds,
        buildsBefore + 1,
        reason: 'the Watch DID rebuild on the duplicate event',
      );
      expect(
        stage.frames,
        hasLength(framesBefore + 1),
        reason: 'a flush pass DID run',
      );
      final f = stage.frames.last;
      expect(
        f.repainted,
        isNotEmpty,
        reason: 'the rects WERE repainted into the back buffer',
      );
      expect(
        f.changes,
        isEmpty,
        reason: 'double-buffer diff dedups the identical repaint',
      );
      expect(f.bytes, isEmpty, reason: 'zero changed cells -> zero bytes');
      expect(
        sink.payloads,
        hasLength(payloadsBefore),
        reason: 'empty frames are not written to the sink',
      );
    });

    test('K successive events -> expected final front buffer; per-frame '
        'diffs small relative to grid size', () async {
      final tickerValues = [1, 2, 3, 42, 137];
      final changedPerFrame = <int>[];
      final bytesPerFrame = <int>[];
      for (final v in tickerValues) {
        fx.ticker.add(v);
        await pumpEventQueue();
        changedPerFrame.add(stage.frames.last.cellsChanged);
        bytesPerFrame.add(stage.frames.last.bytesEmitted);
      }
      fx.feed.add('done');
      await pumpEventQueue();
      changedPerFrame.add(stage.frames.last.cellsChanged);
      bytesPerFrame.add(stage.frames.last.bytesEmitted);

      expect(stage.flushCount, 6);
      expect(stage.grid.frontToString().trimRight(), finalSnapshot);

      final cellCount = stage.grid.cellCount;
      final fullRedraw = stage.encoder.fullRedrawBytes(stage.grid);
      // The per-frame economy record (README quotes these):
      // ignore: avoid_print
      print(
        'typesetting: grid=${stage.grid.width}x'
        '${stage.grid.height} ($cellCount cells); per-frame changed '
        'cells=$changedPerFrame; per-frame ANSI bytes=$bytesPerFrame; '
        'fullRedrawBytes=$fullRedraw',
      );
      for (final n in changedPerFrame) {
        expect(n, greaterThan(0), reason: 'every distinct event changes cells');
        expect(
          n,
          lessThan(cellCount ~/ 10),
          reason:
              'per-frame diff must stay under 10% of the grid '
              '(got $n of $cellCount)',
        );
      }
    });

    test('the static subtree is never rebuilt and never repainted', () async {
      final staticBoxBefore = boxes()[1];
      expect(fx.staticBuilds, 1, reason: 'built exactly once, at mount');
      expect(fx.tickerBuilds, 1);
      expect(fx.feedBuilds, 1);

      fx.ticker.add(1);
      await pumpEventQueue();
      fx.ticker.add(2);
      await pumpEventQueue();
      fx.feed.add('hi');
      await pumpEventQueue();

      expect(
        fx.staticBuilds,
        1,
        reason: 'no stream event may rebuild the static subtree',
      );
      expect(fx.tickerBuilds, 3, reason: 'mount + 2 ticker events');
      expect(fx.feedBuilds, 2, reason: 'mount + 1 feed event');
      expect(
        identical(boxes()[1], staticBoxBefore),
        isTrue,
        reason: 'same render branch instance across all events',
      );
      final staticRect = staticBoxBefore.rect;
      for (final frame in stage.frames.skip(1)) {
        expect(
          frame.repainted.contains(staticRect),
          isFalse,
          reason: 'the static box must never be repainted',
        );
        expect(
          frame.changes.where((c) => staticRect.contains(c.x, c.y)),
          isEmpty,
          reason: 'no frame may change cells inside the static box',
        );
      }
    });

    test('instrumentation carries the VERBATIM flush() return — no side '
        'channels', () async {
      // Locate the ticker Watch branch independently, via the public
      // traversal contract: stage child 0 is the render-scope wrapper; its
      // sole child is the Watch branch.
      final wrappers = <Branch>[];
      stage.visitChildren(wrappers.add);
      expect(wrappers, hasLength(3));
      final tickerWatch = innerOf(wrappers[0]);

      fx.ticker.add(9);
      await pumpEventQueue();

      final f = stage.frames.last;
      // The drained list is exactly the Watch branch the event dirtied
      // (A9-cascade force-rebuilds are excluded by the flush inclusion
      // rule, A14).
      expect(f.rebuilt, hasLength(1));
      expect(
        identical(f.rebuilt.single, tickerWatch),
        isTrue,
        reason: 'FrameRecord.rebuilt must be the verbatim flush return',
      );
    });
  });
}
