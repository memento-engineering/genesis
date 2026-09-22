// HookComponent — the hooks-style stateful primitive. Proves the
// hook dispatch, the rules of hooks, reconcile identity via the HookComponent
// subclass tag, A8 throw-after-unmount, microtask-passive effects, and that a
// counter needs no State class / Watch collapses to one useStream line.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

// --- capture channels (reset per test) -------------------------------------
late List<String> renderLog;
late List<String> effectLog;
StateCell<int>? capturedCell;
int? capturedStream;
HookBuildContext? capturedCtx;
int memoComputes = 0;

// --- test sprouts (each a single class, state inline — the whole point) ----

/// A counter with NO separate State class (the proof artifact).
class _Counter extends HookComponent {
  const _Counter({this.start = 0});
  final int start;
  @override
  Component build(HookBuildContext context) {
    final count = context.useState(start);
    capturedCell = count;
    renderLog.add('c${count.value}');
    return Leaf('c${count.value}');
  }
}

/// `Watch` re-expressed as one `useStream` line (the collapse proof).
class _Streamer extends HookComponent {
  const _Streamer(this.stream, {this.initial = 0});
  final Stream<int> stream;
  final int initial;
  @override
  Component build(HookBuildContext context) {
    final v = context.useStream(stream, initial: initial);
    capturedStream = v;
    renderLog.add('s$v');
    return Leaf('s$v');
  }
}

/// useEffect with a logged run + cleanup, keyed by [keys].
class _Effector extends HookComponent {
  const _Effector(this.keys);
  final List<Object?>? keys;
  @override
  Component build(HookBuildContext context) {
    context.useEffect(() {
      effectLog.add('run');
      return () => effectLog.add('cleanup');
    }, keys);
    return const Leaf('e');
  }
}

/// An effect that bumps a state cell on mount — exercises the flush invariant.
class _EffectBumper extends HookComponent {
  const _EffectBumper();
  @override
  Component build(HookBuildContext context) {
    final count = context.useState(0);
    capturedCell = count;
    context.useEffect(() {
      count.value = count.value + 1;
      return null;
    }, const []);
    renderLog.add('b${count.value}');
    return Leaf('b${count.value}');
  }
}

class _Memoizer extends HookComponent {
  const _Memoizer(this.key0);
  final Object key0;
  @override
  Component build(HookBuildContext context) {
    final v = context.useMemo(() {
      memoComputes++;
      return '$key0'.length;
    }, [key0]);
    renderLog.add('m$v');
    return const Leaf('m');
  }
}

/// Calls a variable number of hooks — for count-drift detection.
class _Drift extends HookComponent {
  const _Drift(this.extra);
  final bool extra;
  @override
  Component build(HookBuildContext context) {
    context.useState(0);
    if (extra) context.useState(1);
    return const Leaf('d');
  }
}

/// Calls hooks in a swappable order — for order/type-drift detection.
class _Order extends HookComponent {
  const _Order(this.swap);
  final bool swap;
  @override
  Component build(HookBuildContext context) {
    if (swap) {
      context.useMemo(() => 1, const []);
      context.useState(0);
    } else {
      context.useState(0);
      context.useMemo(() => 1, const []);
    }
    return const Leaf('o');
  }
}

/// Captures its [HookBuildContext] so a test can call a hook outside build.
class _Capture extends HookComponent {
  const _Capture();
  @override
  Component build(HookBuildContext context) {
    capturedCtx = context;
    context.useState(0);
    return const Leaf('cap');
  }
}

/// Hook 0 = a stream (must still cancel); hook 1 = an effect whose cleanup
/// throws — exercises the guarded-unmount invariant.
class _ThrowOnCleanup extends HookComponent {
  const _ThrowOnCleanup(this.stream);
  final Stream<int> stream;
  @override
  Component build(HookBuildContext context) {
    context.useStream(stream, initial: 0);
    context.useEffect(
      () =>
          () => throw StateError('cleanup boom'),
      const [],
    );
    return const Leaf('t');
  }
}

/// Two keyed effects — proves the two-phase (all cleanups, then all effects).
class _TwoEffects extends HookComponent {
  const _TwoEffects(this.key0);
  final Object key0;
  @override
  Component build(HookBuildContext context) {
    context.useEffect(() {
      effectLog.add('runA');
      return () => effectLog.add('cleanA');
    }, [key0]);
    context.useEffect(() {
      effectLog.add('runB');
      return () => effectLog.add('cleanB');
    }, [key0]);
    return const Leaf('two');
  }
}

/// Illegally sets a cell during build (should assert).
class _SetDuringBuild extends HookComponent {
  const _SetDuringBuild();
  @override
  Component build(HookBuildContext context) {
    context.useState(0).value = 1;
    return const Leaf('x');
  }
}

void main() {
  setUp(() {
    renderLog = [];
    effectLog = [];
    capturedCell = null;
    capturedStream = null;
    capturedCtx = null;
    memoComputes = 0;
  });

  group('useState', () {
    test('setting value marks a rebuild; flush re-runs build', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _Counter());
      expect(renderLog, ['c0']);

      capturedCell!.value = 5;
      owner.flush();
      expect(renderLog, ['c0', 'c5']);
    });

    test('functional set applies to the previous value', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _Counter(start: 1));
      capturedCell!.set((p) => p + 10);
      owner.flush();
      expect(renderLog.last, 'c11');
    });

    test('value persists across a config update (A9); new initial ignored', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _Counter(start: 0));
      capturedCell!.value = 7;
      owner.flush();
      expect(renderLog.last, 'c7');

      // Update with a DIFFERENT start — the persisted 7 must survive.
      root.update(const _Counter(start: 99));
      expect(renderLog.last, 'c7');
    });
  });

  group('useStream (the Watch collapse)', () {
    test('returns initial before first emit, then latest after emit+flush', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(_Streamer(ctrl.stream, initial: 42));
      expect(capturedStream, 42);

      ctrl.add(10);
      owner.flush();
      expect(capturedStream, 10);
    });

    test('resubscribes when the source changes, keeping the last value', () {
      var listensA = 0, cancelsA = 0, listensB = 0;
      final a = StreamController<int>(
        sync: true,
        onListen: () => listensA++,
        onCancel: () => cancelsA++,
      );
      final b = StreamController<int>(sync: true, onListen: () => listensB++);
      addTearDown(a.close);
      addTearDown(b.close);
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      final root = owner.mountRoot(_Streamer(a.stream));
      a.add(5);
      owner.flush();
      expect((listensA, capturedStream), (1, 5));

      root.update(_Streamer(b.stream)); // swap source
      expect(cancelsA, 1, reason: 'old subscription cancelled');
      expect(listensB, 1, reason: 'new subscription opened');
      expect(capturedStream, 5, reason: 'last value kept across the swap');

      a.add(99);
      owner.flush();
      expect(capturedStream, 5, reason: 'old stream no longer drives rebuilds');
      b.add(7);
      owner.flush();
      expect(capturedStream, 7);
    });

    test(
      'does NOT resubscribe when the source is unchanged (same controller)',
      () {
        var listens = 0, cancels = 0;
        final c = StreamController<int>(
          sync: true,
          onListen: () => listens++,
          onCancel: () => cancels++,
        );
        addTearDown(c.close);
        final owner = BuildOwner();
        addTearDown(owner.dispose);

        final root = owner.mountRoot(_Streamer(c.stream));
        root.update(_Streamer(c.stream)); // == same controller stream
        expect((listens, cancels), (1, 0));
      },
    );

    test('cancels the subscription on unmount', () {
      var cancels = 0;
      final c = StreamController<int>(sync: true, onCancel: () => cancels++);
      addTearDown(c.close);
      final owner = BuildOwner();

      owner.mountRoot(_Streamer(c.stream));
      owner.unmountRoot();
      expect(cancels, 1);

      renderLog.clear();
      c.add(9); // no live subscriber
      expect(renderLog, isEmpty);
    });
  });

  group('useEffect (microtask-passive)', () {
    test('runs after mount, in a microtask (not synchronously)', () async {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _Effector([]));
      expect(effectLog, isEmpty, reason: 'effect is deferred, not synchronous');

      await Future<void>.delayed(Duration.zero);
      expect(effectLog, ['run']);
    });

    test(
      're-runs on key change (cleanup first), not on unrelated rebuild',
      () async {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(const _Effector([1]));
        await Future<void>.delayed(Duration.zero);
        expect(effectLog, ['run']);

        root.update(const _Effector([1])); // same key -> no re-run
        await Future<void>.delayed(Duration.zero);
        expect(effectLog, ['run']);

        root.update(const _Effector([2])); // new key -> cleanup then run
        await Future<void>.delayed(Duration.zero);
        expect(effectLog, ['run', 'cleanup', 'run']);
      },
    );

    test('teardown runs on unmount', () async {
      final owner = BuildOwner();
      owner.mountRoot(const _Effector([]));
      await Future<void>.delayed(Duration.zero);
      effectLog.clear();

      owner.unmountRoot();
      expect(effectLog, ['cleanup']);
    });

    test(
      "an effect's markNeedsRebuild does not trip the flush assert",
      () async {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(const _EffectBumper()); // build 0; effect scheduled
        expect(renderLog, ['b0']);

        await Future<void>.delayed(Duration.zero); // effect bumps -> dirties
        expect(
          owner.flush,
          returnsNormally,
          reason: 'effect re-dirty landed in a fresh pass',
        );
        expect(renderLog.last, 'b1');
      },
    );

    test('deferred effect is skipped if the element unmounts first', () async {
      final owner = BuildOwner();
      owner.mountRoot(const _Effector([]));
      owner.unmountRoot(); // before the microtask drains
      await Future<void>.delayed(Duration.zero);
      expect(effectLog, isEmpty, reason: 'never ran -> no cleanup either');
    });

    test(
      'two-phase: all cleanups run before all effects on a key change',
      () async {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(const _TwoEffects('x'));
        await Future<void>.delayed(Duration.zero);
        expect(effectLog, ['runA', 'runB']);
        effectLog.clear();

        root.update(const _TwoEffects('y')); // key change -> both re-run
        await Future<void>.delayed(Duration.zero);
        expect(
          effectLog,
          ['cleanA', 'cleanB', 'runA', 'runB'],
          reason: 'cleanups (both) precede effects (both), not interleaved',
        );
      },
    );

    test(
      'a throwing effect cleanup still cancels a sibling stream + surfaces',
      () async {
        var cancels = 0;
        final c = StreamController<int>(sync: true, onCancel: () => cancels++);
        addTearDown(c.close);
        final owner = BuildOwner();
        owner.mountRoot(_ThrowOnCleanup(c.stream));
        await Future<void>.delayed(
          Duration.zero,
        ); // effect registers the cleanup

        expect(
          owner.unmountRoot,
          throwsStateError,
          reason: 'cleanup error surfaces',
        );
        expect(
          cancels,
          1,
          reason: 'sibling stream cancelled despite the throw',
        );
      },
    );
  });

  group('useMemo', () {
    test('recomputes only when keys change', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _Memoizer('aa'));
      expect(memoComputes, 1);

      root.update(const _Memoizer('aa')); // same key
      expect(memoComputes, 1);

      root.update(const _Memoizer('bbbb')); // new key
      expect(memoComputes, 2);
      expect(renderLog.last, 'm4');
    });
  });

  group('rules of hooks', () {
    test('calling MORE hooks than last build throws', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _Drift(false));
      expect(() => root.update(const _Drift(true)), throwsStateError);
    });

    test('calling FEWER hooks throws (always-on, not debug-only)', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _Drift(true));
      expect(() => root.update(const _Drift(false)), throwsStateError);
    });

    test('setting a StateCell during build asserts', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      expect(
        () => owner.mountRoot(const _SetDuringBuild()),
        throwsA(isA<AssertionError>()),
      );
    });

    test('changing hook order/type throws', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _Order(false));
      expect(() => root.update(const _Order(true)), throwsStateError);
    });

    test('calling a hook outside build asserts', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _Capture());
      expect(() => capturedCtx!.useState(0), throwsA(isA<AssertionError>()));
    });
  });

  group('reconcile identity (the HookComponent subclass is the tag)', () {
    test('same subclass + slot updates in place; state persists', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root =
          owner.mountRoot(Node('root', children: const [_Counter()]))
              as NodeElement;
      final before = root.children.single;
      capturedCell!.value = 3;
      owner.flush();

      root.update(Node('root', children: const [_Counter()]));
      final after = root.children.single;
      expect(identical(after, before), isTrue);
      expect(renderLog.last, 'c3', reason: 'state survived the reconcile');
    });

    test('different subclass at the same slot is replaced', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root =
          owner.mountRoot(Node('root', children: const [_Counter()]))
              as NodeElement;
      final before = root.children.single;

      root.update(Node('root', children: [_Streamer(ctrl.stream)]));
      final after = root.children.single;
      expect(before.mounted, isFalse);
      expect(after, isA<HookElement>());
      expect(identical(after, before), isFalse);
    });
  });

  group('A8 handle', () {
    test('HookBuildContext is a handle, not the element', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _Capture());
      expect(capturedCtx, isA<BuildContext>());
      expect(capturedCtx, isNot(isA<Element>()));
    });

    test('HookBuildContext.markNeedsRebuild throws after unmount', () {
      final owner = BuildOwner();
      owner.mountRoot(const _Capture());
      final ctx = capturedCtx!;
      owner.unmountRoot();
      expect(ctx.markNeedsRebuild, throwsStateError);
    });

    test(
      'HookBuildContext delegates getInheritedValueOfExactType (no dep)',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final root =
            owner.mountRoot(
                  InheritedComponent<String>(
                    value: 'ambient',
                    child: const _Capture(),
                  ),
                )
                as InheritedElement<String>;
        expect(capturedCtx!.getInheritedValueOfExactType<String>(), 'ambient');
        expect(root.dependents, isEmpty);
      },
    );
  });

  group('BuildOwner integration (ADR-0005 test b2)', () {
    test('a state change auto-flushes via onNeedsFlush microtask', () async {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.onNeedsFlush = () => scheduleMicrotask(owner.flush);
      owner.mountRoot(const _Counter());

      capturedCell!.value = 8; // no manual flush
      await Future<void>.delayed(Duration.zero);
      expect(renderLog.last, 'c8');
    });
  });
}
