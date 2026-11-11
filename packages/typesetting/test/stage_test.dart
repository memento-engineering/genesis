/// The locality suite against the real, tree-resident live loop (register
/// A23): stream event -> dirty set -> onNeedsFlush -> microtask frame pass
/// -> owner.flush() -> flow relayout -> repaint exactly the dirty render
/// elements' rects -> double-buffered diff -> minimal ANSI.
///
/// There is no side-car driver and no paint delegate: the render elements
/// paint as their artifact response, and the FrameRecord carries the
/// verbatim flush return.
library;

import 'dart:async';

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

/// The sole child of [element], via the public traversal contract.
Element innerOf(Element element) {
  late Element inner;
  var count = 0;
  element.visitChildren((child) {
    inner = child;
    count++;
  });
  expect(count, 1, reason: 'expected exactly one child under $element');
  return inner;
}

/// Fault and counter hooks for one [_ProbeText]. Test-only: the probe is the
/// shipped [Text] leaf with fault injection, not a new node vocabulary.
class _Probe {
  /// When set, the probe's paint calls [beforeThrow] and then throws.
  bool throwOnPaint = false;

  /// When set, the probe's layout throws.
  bool throwOnLayout = false;

  /// Layout passes the probe has run.
  int layouts = 0;

  /// Called just before a paint throw.
  void Function()? beforeThrow;

  /// The mounted probe element.
  _ProbeTextElement? element;
}

/// The real [Text] leaf, mounting a [_ProbeTextElement].
class _ProbeText extends Text {
  const _ProbeText(this.probe, super.content);

  final _Probe probe;

  @override
  TextElement createElement() => _ProbeTextElement(this);
}

/// The real [TextElement], plus [_Probe]'s fault and counter hooks.
class _ProbeTextElement extends TextElement {
  _ProbeTextElement(_ProbeText super.component);

  _Probe get _probe => (component as _ProbeText).probe;

  @override
  void mount(Element? parent, Object? slot) {
    _probe.element = this;
    super.mount(parent, slot);
  }

  @override
  void paint(CellGrid grid) {
    if (_probe.throwOnPaint) {
      _probe.beforeThrow?.call();
      throw StateError('probe paint');
    }
    super.paint(grid);
  }

  @override
  void performLayout() {
    _probe.layouts++;
    if (_probe.throwOnLayout) throw StateError('probe layout');
    super.performLayout();
  }
}

/// Byte sink fake that records payloads and calls [onAdd] after each one.
class _HookSink implements Sink<List<int>> {
  final List<List<int>> payloads = [];
  void Function()? onAdd;

  @override
  void add(List<int> data) {
    payloads.add(data);
    onAdd?.call();
  }

  @override
  void close() {}
}

void main() {
  group('Stage live loop', () {
    late LocalityFixture fx;
    late RecordingSink sink;
    late BuildOwner owner;
    late StageElement stage;

    setUp(() {
      sink = RecordingSink();
      fx = LocalityFixture(sink: sink);
      owner = BuildOwner();
      stage = owner.mountRoot(fx.stageSeed) as StageElement;
    });

    tearDown(() async {
      owner.dispose();
      await fx.dispose();
    });

    /// The top-level render boxes, in render-tree (flow) order:
    /// 0 = ticker, 1 = static, 2 = feed.
    List<RenderElement> boxes() => stage.renderChildren;

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
        'confined to the rebuilt render element\'s rect (LOCALITY)', () async {
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
          reason: '$c escaped the rebuilt render element\'s rect $tickerRect',
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
        reason: 'same render element instance across all events',
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
      // Locate the ticker Watch element independently, via the public
      // traversal contract: stage child 0 is the render-scope wrapper; its
      // sole child is the Watch element.
      final wrappers = <Element>[];
      stage.visitChildren(wrappers.add);
      expect(wrappers, hasLength(3));
      final tickerWatch = innerOf(wrappers[0]);

      fx.ticker.add(9);
      await pumpEventQueue();

      final f = stage.frames.last;
      // The drained list is exactly the Watch element the event dirtied
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

  group('Stage follow-up frames', () {
    late List<BuildOwner> owners;
    late List<Future<void> Function()> closers;
    late _HookSink sink;
    void Function(FrameRecord frame)? onFrameHook;

    setUp(() {
      owners = [];
      closers = [];
      sink = _HookSink();
      onFrameHook = null;
    });

    tearDown(() async {
      for (final owner in owners) {
        owner.dispose();
      }
      for (final close in closers) {
        await close();
      }
    });

    StreamController<T> controller<T>() {
      final c = StreamController<T>();
      closers.add(c.close);
      return c;
    }

    StageElement mountStage(List<Component> children) {
      final owner = BuildOwner();
      owners.add(owner);
      return owner.mountRoot(
            Stage(
              width: 20,
              height: 8,
              sink: sink,
              children: children,
              onFrame: (frame) => onFrameHook?.call(frame),
            ),
          )
          as StageElement;
    }

    test('a repaint requested from onFrame gets exactly one follow-up '
        'frame', () async {
      final events = controller<String>();
      final stage = mountStage([
        Watch<String>(events.stream, (v) => Text(v), initialValue: 'a'),
        const Text('b'),
      ]);
      await pumpEventQueue();
      expect(stage.frames, hasLength(1));
      final b = stage.renderChildren[1];
      onFrameHook = (frame) {
        onFrameHook = null;
        b.markNeedsPaint();
      };

      events.add('x');
      await pumpEventQueue();

      expect(stage.frames, hasLength(3), reason: 'frame 1 + one follow-up');
      expect(stage.frames[2].repainted, {b.rect});
      expect(stage.flushCount, 2);
      await pumpEventQueue();
      expect(stage.frames, hasLength(3), reason: 'no further frame');
    });

    test('a repaint requested from the sink add gets exactly one follow-up '
        'frame', () async {
      final events = controller<String>();
      final stage = mountStage([
        Watch<String>(events.stream, (v) => Text(v), initialValue: 'a'),
        const Text('b'),
      ]);
      await pumpEventQueue();
      final b = stage.renderChildren[1];
      sink.onAdd = () {
        sink.onAdd = null;
        b.markNeedsPaint();
      };

      events.add('x');
      await pumpEventQueue();

      expect(stage.frames, hasLength(3));
      expect(stage.frames[1].bytes, isNotEmpty, reason: 'the sink was fed');
      expect(stage.frames[2].repainted, {b.rect});
      await pumpEventQueue();
      expect(stage.frames, hasLength(3), reason: 'no further frame');
    });

    test('a repaint requested from onFrame during frame 0 gets exactly one '
        'follow-up frame', () async {
      final probe = _Probe();
      onFrameHook = (frame) {
        onFrameHook = null;
        probe.element!.markNeedsPaint();
      };
      final stage = mountStage([_ProbeText(probe, 'p'), const Text('b')]);
      expect(stage.frames, hasLength(1));

      await pumpEventQueue();
      expect(stage.frames, hasLength(2));
      expect(stage.frames[1].repainted, {probe.element!.rect});
      await pumpEventQueue();
      expect(stage.frames, hasLength(2), reason: 'no further frame');
    });

    test('a repaint requested from a component build during flush is '
        'painted in that same pass', () async {
      final events = controller<String>();
      late RenderElement target;
      final stage = mountStage([
        Watch<String>(events.stream, (value) {
          // Deliberately impure and test-only: a build-time repaint request
          // is one of the covered sources under test.
          if (value == 'poke') target.markNeedsPaint();
          return Text(value);
        }, initialValue: 'idle'),
        const Text('t'),
      ]);
      await pumpEventQueue();
      target = stage.renderChildren[1];

      events.add('poke');
      await pumpEventQueue();

      expect(stage.frames, hasLength(2));
      expect(stage.frames[1].repainted, contains(target.rect));
      await pumpEventQueue();
      expect(
        stage.frames,
        hasLength(2),
        reason: 'the running pass consumed the request',
      );
    });

    test('three requests raised within one pass coalesce into one follow-up '
        'frame', () async {
      final events = controller<String>();
      final stage = mountStage([
        Watch<String>(events.stream, (v) => Text(v), initialValue: 'a'),
        const Text('b'),
      ]);
      await pumpEventQueue();
      final wrappers = <Element>[];
      stage.visitChildren(wrappers.add);
      final watch = innerOf(wrappers[0]);
      final b = stage.renderChildren[1];
      onFrameHook = (frame) {
        onFrameHook = null;
        b.markNeedsPaint();
        stage.markNeedsLayout();
        watch.markNeedsRebuild();
      };

      events.add('x');
      await pumpEventQueue();

      expect(stage.frames, hasLength(3), reason: 'frame 1 + one follow-up');
      expect(stage.flushCount, 2);
      final followUp = stage.frames[2];
      expect(followUp.rebuilt, hasLength(1));
      expect(identical(followUp.rebuilt.single, watch), isTrue);
      expect(followUp.repainted, contains(b.rect));
      await pumpEventQueue();
      expect(stage.frames, hasLength(3), reason: 'no further frame');
    });

    test('a pass whose layout moves rects buys no follow-up frame', () async {
      final counts = controller<int>();
      final stage = mountStage([
        Watch<int>(
          counts.stream,
          (n) => Box(
            title: 'g',
            children: [
              for (var i = 0; i < n; i++) Text('line $i', key: ValueKey(i)),
            ],
          ),
          initialValue: 1,
        ),
        const Text('tail'),
      ]);
      await pumpEventQueue();
      expect(stage.frames, hasLength(1), reason: 'mount buys only frame 0');
      expect(stage.flushCount, 0);
      final tail = stage.renderChildren[1];
      final tailBefore = tail.rect;

      counts.add(3);
      await pumpEventQueue();

      expect(tail.rect, isNot(tailBefore), reason: 'the relayout moved it');
      expect(stage.frames, hasLength(2));
      expect(stage.flushCount, 1);
      await pumpEventQueue();
      expect(stage.frames, hasLength(2), reason: 'no further frame');
    });

    test('a throwing paint reaches the zone, schedules no follow-up, and '
        'keeps unpainted elements queued', () async {
      final probe = _Probe();
      final stage = mountStage([
        _ProbeText(probe, 'p'),
        const Box(title: 'v', children: [Text('victim')]),
      ]);
      await pumpEventQueue();
      final thrower = probe.element!;
      final victim = stage.renderChildren[1].renderChildren.single;
      expect(
        thrower.depth,
        lessThan(victim.depth),
        reason: 'the thrower drains before the deeper victim',
      );
      final errors = <Object>[];
      runZonedGuarded(() {
        probe.throwOnPaint = true;
        probe.beforeThrow = thrower.markNeedsLayout;
        victim.markNeedsPaint();
        thrower.markNeedsPaint();
      }, (error, _) => errors.add(error));

      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(
        stage.frames,
        hasLength(1),
        reason:
            'the throwing pass records nothing and buys no follow-up, '
            'despite the relayout its paint requested',
      );

      // The thrower stays armed: a retry would throw outside the zone.
      stage.markNeedsLayout();
      await pumpEventQueue();

      expect(stage.frames, hasLength(2));
      expect(stage.frames.last.repainted, {victim.rect});
      expect(errors, hasLength(1), reason: 'the thrower is not retried');
    });

    test('a throwing layout keeps the relayout flagged for the next '
        'pass', () async {
      final probe = _Probe();
      final stage = mountStage([_ProbeText(probe, 'p'), const Text('s')]);
      await pumpEventQueue();
      final sibling = stage.renderChildren[1];
      final errors = <Object>[];
      runZonedGuarded(() {
        probe.throwOnLayout = true;
        stage.markNeedsLayout();
      }, (error, _) => errors.add(error));

      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(stage.frames, hasLength(1), reason: 'no follow-up frame');

      probe.throwOnLayout = false;
      final layoutsBefore = probe.layouts;
      sibling.markNeedsPaint();
      await pumpEventQueue();

      expect(
        probe.layouts,
        layoutsBefore + 1,
        reason: 'the unfinished relayout runs in the next pass',
      );
      expect(stage.frames, hasLength(2));
    });

    test('a throwing frame 0 propagates out of mount and the pass its mount '
        'builds queued does not retry it', () async {
      final probe = _Probe()..throwOnLayout = true;
      final errors = <Object>[];
      Object? mountError;
      runZonedGuarded(() {
        try {
          mountStage([_ProbeText(probe, 'p'), const Text('s')]);
        } on StateError catch (e) {
          mountError = e;
        }
      }, (error, _) => errors.add(error));
      expect(mountError, isA<StateError>());
      expect(probe.layouts, 1);

      await pumpEventQueue();

      expect(
        probe.layouts,
        1,
        reason: 'the queued mount-time pass must not re-run the layout',
      );
      expect(errors, isEmpty, reason: 'no automatic retry threw again');
      expect(probe.element!.binding!.frames, isEmpty);
    });

    test('a detached binding schedules nothing for a request', () async {
      final stage = mountStage([const Text('a')]);
      await pumpEventQueue();
      owners.single.dispose();
      final binding = stage.binding!;
      binding.scheduleRepaint(stage);
      binding.scheduleRelayout();
      await pumpEventQueue();
      expect(stage.frames, hasLength(1));

      final events = controller<String>();
      final second = mountStage([
        Watch<String>(events.stream, (v) => Text(v), initialValue: 'a'),
        const Text('b'),
      ]);
      await pumpEventQueue();
      final b = second.renderChildren[1];
      final secondOwner = owners.last;
      onFrameHook = (frame) {
        onFrameHook = null;
        b.markNeedsPaint();
        secondOwner.dispose();
      };

      events.add('x');
      await pumpEventQueue();
      await pumpEventQueue();

      expect(
        second.frames,
        hasLength(2),
        reason: 'frame 1 only; the detach dropped the in-pass request',
      );
    });
  });
}
