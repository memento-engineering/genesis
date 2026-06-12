/// The spike-4 locality suite against the REAL `TreeOwner.flush()` (ADR-0004
/// Decision 2 + Decision 4): stream event -> dirty set -> onNeedsFlush ->
/// microtask flush -> drained list -> delegate region mapping -> targeted
/// repaint -> double-buffered diff -> minimal ANSI.
///
/// Spike 4's documented fake — builder-driven dirty-region marking via a
/// RepaintNotifier, needed because the owner's dirty set was private — is
/// gone: regions come only from the flush return (ADR-0001 Decision 5).
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';
import 'src/snapshots.dart';

void main() {
  group('Typesetter live loop', () {
    late LocalityFixture fx;
    late BoxDelegate delegate;
    late RecordingSink sink;
    late Typesetter typesetter;

    setUp(() {
      fx = LocalityFixture();
      delegate = BoxDelegate(width: 40);
      sink = RecordingSink();
      typesetter = Typesetter(
        delegate: delegate,
        width: 40,
        height: 12,
        sink: sink,
      );
      typesetter.mount(fx.root);
    });

    tearDown(() async {
      typesetter.dispose();
      await fx.dispose();
    });

    /// The three top-level branches under the root, via the public
    /// traversal contract.
    List<Branch> topChildren() {
      final children = <Branch>[];
      typesetter.root.visitChildren(children.add);
      return children;
    }

    test('initial frame paints the full scene', () {
      expect(typesetter.frames, hasLength(1));
      expect(
        typesetter.flushCount,
        0,
        reason: 'frame 0 is a paint, not a flush',
      );
      final f0 = typesetter.frames[0];
      expect(f0.rebuilt, isEmpty, reason: 'nothing flushed at mount');
      expect(f0.repainted, typesetter.regions.toSet());
      expect(f0.changes, isNotEmpty);
      expect(f0.bytes, isNotEmpty);
      expect(sink.payloads, hasLength(1));
      expect(typesetter.grid.frontToString(), initialSnapshot);
    });

    test('one stream event -> exactly one flush pass; changed cells confined '
        'to the watched region (LOCALITY)', () async {
      fx.ticker.add(7);
      await pumpEventQueue();

      expect(
        typesetter.flushCount,
        1,
        reason: 'one event must cost one flush pass',
      );
      expect(typesetter.frames, hasLength(2));
      final f = typesetter.frames[1];
      expect(f.repainted, {
        typesetter.regions[0],
      }, reason: 'only the ticker region repaints');
      expect(f.changes, isNotEmpty);

      final tickerRect = typesetter.regions[0].rect;
      final staticRect = typesetter.regions[1].rect;
      final feedRect = typesetter.regions[2].rect;
      for (final c in f.changes) {
        expect(
          tickerRect.contains(c.x, c.y),
          isTrue,
          reason: '$c escaped the watched region $tickerRect',
        );
      }
      expect(
        f.changes.where((c) => staticRect.contains(c.x, c.y)),
        isEmpty,
        reason: 'zero cells may change inside the static region',
      );
      expect(
        f.changes.where((c) => feedRect.contains(c.x, c.y)),
        isEmpty,
        reason: 'zero cells may change inside the other live region',
      );

      // Economy: the diff frame must be far cheaper than a full redraw.
      final fullRedraw = typesetter.encoder.fullRedrawBytes(typesetter.grid);
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
      final framesBefore = typesetter.frames.length;
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
        typesetter.frames,
        hasLength(framesBefore + 1),
        reason: 'a flush pass DID run',
      );
      final f = typesetter.frames.last;
      expect(f.repainted, {
        typesetter.regions[0],
      }, reason: 'the region WAS repainted into the back buffer');
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
        changedPerFrame.add(typesetter.frames.last.cellsChanged);
        bytesPerFrame.add(typesetter.frames.last.bytesEmitted);
      }
      fx.feed.add('done');
      await pumpEventQueue();
      changedPerFrame.add(typesetter.frames.last.cellsChanged);
      bytesPerFrame.add(typesetter.frames.last.bytesEmitted);

      expect(typesetter.flushCount, 6);
      expect(typesetter.grid.frontToString(), finalSnapshot);

      final cellCount = typesetter.grid.cellCount;
      final fullRedraw = typesetter.encoder.fullRedrawBytes(typesetter.grid);
      // The per-frame economy record (README quotes these):
      // ignore: avoid_print
      print(
        'typesetting: grid=${typesetter.grid.width}x'
        '${typesetter.grid.height} ($cellCount cells); per-frame changed '
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

    test('the static subtree is never rebuilt', () async {
      final staticBranchBefore = topChildren()[1];
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
        identical(topChildren()[1], staticBranchBefore),
        isTrue,
        reason: 'same branch instance across all events',
      );
      for (final frame in typesetter.frames.skip(1)) {
        expect(
          frame.repainted.contains(typesetter.regions[1]),
          isFalse,
          reason: 'the static region must never be repainted',
        );
      }
    });

    test('flush mapping: repainted regions derive from the verbatim drained '
        'list, not any side channel', () async {
      fx.ticker.add(9);
      await pumpEventQueue();

      final f = typesetter.frames.last;
      // The drained list is exactly the Watch branch the event dirtied —
      // located independently via the public traversal contract.
      expect(f.rebuilt, hasLength(1));
      expect(
        identical(f.rebuilt.single, topChildren()[0]),
        isTrue,
        reason: 'the rebuilt branch must be the ticker Watch branch',
      );
      // And the repainted set is exactly the delegate mapping of that list.
      expect(
        f.repainted,
        f.rebuilt.map(delegate.regionFor).whereType<Region>().toSet(),
      );
    });
  });

  group('TreeOwner.flush -> delegate mapping (no Typesetter in the loop)', () {
    test('the regions come from the real owner.flush() return', () async {
      final fx = LocalityFixture();
      final owner = TreeOwner();
      var needsFlushEdges = 0;
      owner.onNeedsFlush = () => needsFlushEdges++;
      final root = owner.mountRoot(fx.root);
      final delegate = BoxDelegate(width: 40);
      final regions = delegate.assignRegions(root);

      fx.ticker.add(5);
      await pumpEventQueue();
      expect(
        needsFlushEdges,
        1,
        reason: 'one event -> one empty->non-empty edge',
      );

      final rebuilt = owner.flush();
      expect(
        rebuilt,
        isNotEmpty,
        reason: 'flush must hand the backend what rebuilt',
      );
      final mapped = rebuilt.map(delegate.regionFor).whereType<Region>();
      expect(
        mapped.toSet(),
        {regions[0]},
        reason: 'the drained list maps to exactly the ticker region',
      );

      expect(
        owner.flush(),
        isEmpty,
        reason: 'the dirty set was drained by the previous flush',
      );

      owner.dispose();
      await fx.dispose();
    });
  });
}
