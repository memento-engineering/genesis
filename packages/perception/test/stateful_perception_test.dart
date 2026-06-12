// Conformance port of lenny perception's stateful_perception_test.dart
// (A10 gate). One test carries an A8 delta (the separate-handle fork,
// ADR-0001 Decision 2) — see docs/CONFORMANCE-DELTA.md.
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

// --- fixtures ---

class _Leaf extends Perception {
  const _Leaf();
  @override
  _LeafElement createElement() => _LeafElement(this);
}

class _LeafElement extends PerceptionElement {
  _LeafElement(super.p);
}

class _TrackedPerception extends StatefulPerception {
  const _TrackedPerception();
  @override
  _TrackedState createState() => _TrackedState();
}

class _TrackedState extends PerceptionState<_TrackedPerception> {
  final calls = <String>[];
  int count = 0;

  @override
  void initState() => calls.add('initState');

  @override
  void didChangeDependencies() => calls.add('dcd');

  @override
  Seed build(PerceptionContext context) {
    calls.add('build');
    return const _Leaf();
  }

  @override
  void dispose() => calls.add('dispose');
}

class _ReaderPerception extends StatefulPerception {
  const _ReaderPerception();
  @override
  _ReaderState createState() => _ReaderState();
}

class _ReaderState extends PerceptionState<_ReaderPerception> {
  final calls = <String>[];
  int? lastValue;

  @override
  void didChangeDependencies() {
    calls.add('dcd');
    lastValue = context.dependOnInheritedSeedOfExactType<int>();
  }

  @override
  Seed build(PerceptionContext context) {
    calls.add('build');
    return const _Leaf();
  }
}

// --- tests ---

void main() {
  group('StatefulPerception', () {
    test('createBranch returns StatefulPerceptionElement', () {
      expect(
        const _TrackedPerception().createBranch(),
        isA<StatefulPerceptionElement>(),
      );
    });
  });

  group('StatefulPerceptionElement lifecycle on mount', () {
    test('order: initState → didChangeDependencies → build', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(const _TrackedPerception())
              as StatefulPerceptionElement;
      expect(
        (el.state as _TrackedState).calls,
        equals(['initState', 'dcd', 'build']),
      );
    });

    test('state.perception is the StatefulPerception config', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(const _TrackedPerception())
              as StatefulPerceptionElement;
      expect(el.state.perception, isA<_TrackedPerception>());
    });

    test(
      'state.context is the capability handle bound to the element (A8)',
      () {
        final owner = PerceptionOwner();
        addTearDown(owner.dispose);
        final el =
            owner.mountRoot(const _TrackedPerception())
                as StatefulPerceptionElement;
        final context = (el.state as _TrackedState).context;
        // The handle carries the domain capabilities and delegates to the
        // element...
        expect(context, isA<PerceptionContext>());
        expect(context.perceptionId, equals(el.branchId));
        // ...but is never the element itself (A8: the separate-handle fork —
        // lenny asserted `state.context` WAS the element here).
        expect(context, isNot(same(el)));
        expect(context, isNot(isA<Branch>()));
      },
    );
  });

  group('perceived() sink', () {
    test('perceived() marks element dirty and rebuild runs state.build', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(const _TrackedPerception())
              as StatefulPerceptionElement;
      final state = el.state as _TrackedState;
      state.calls.clear();

      state.perceived(() => state.count++);
      expect(state.count, equals(1));
      owner.flushHarvest();
      expect(state.calls, equals(['build']));
    });

    test('perceived() does not fire didChangeDependencies', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(const _TrackedPerception())
              as StatefulPerceptionElement;
      final state = el.state as _TrackedState;
      state.calls.clear();

      state.perceived(() {});
      owner.flushHarvest();
      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });

  group('dispose lifecycle', () {
    test('dispose() called on unmount', () {
      final owner = PerceptionOwner();
      final el =
          owner.mountRoot(const _TrackedPerception())
              as StatefulPerceptionElement;
      final state = el.state as _TrackedState;
      state.calls.clear();

      owner.unmountRoot();
      expect(state.calls, equals(['dispose']));
    });

    test(
      'dispose() called before super.unmount() (element still mounted during dispose)',
      () {
        final owner = PerceptionOwner();
        final el =
            owner.mountRoot(const _TrackedPerception())
                as StatefulPerceptionElement;

        owner.unmountRoot();
        expect(el.mounted, isFalse);
      },
    );
  });

  group('didChangeDependencies on InheritedPerception change', () {
    test('fires before build when inherited value changes', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedPerception<int>(
                  value: 1,
                  child: const _ReaderPerception(),
                ),
              )
              as InheritedPerceptionElement<int>;

      final readerEl = root.childBranch as StatefulPerceptionElement;
      final state = readerEl.state as _ReaderState;

      // Initial mount: dcd called with value=1
      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(1));
      state.calls.clear();

      // Update inherited value → triggers dependencyChanged → rebuild with dcd
      root.update(
        InheritedPerception<int>(value: 2, child: const _ReaderPerception()),
      );
      owner.flushHarvest();

      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(2));
    });

    test('does not fire dcd on perceived()-driven rebuild', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedPerception<int>(
                  value: 1,
                  child: const _ReaderPerception(),
                ),
              )
              as InheritedPerceptionElement<int>;

      final readerEl = root.childBranch as StatefulPerceptionElement;
      final state = readerEl.state as _ReaderState;
      state.calls.clear();

      // perceived()-driven rebuild: no dependency change
      state.perceived(() {});
      owner.flushHarvest();

      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });
}
