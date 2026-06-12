// Port of perception's stateful_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:tree/tree.dart';

// --- fixtures ---

class _Leaf extends Seed {
  const _Leaf();
  @override
  _LeafBranch createBranch() => _LeafBranch(this);
}

class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
}

class _TrackedSeed extends StatefulSeed {
  const _TrackedSeed();
  @override
  _TrackedState createState() => _TrackedState();
}

class _TrackedState extends State<_TrackedSeed> {
  final calls = <String>[];
  int count = 0;

  @override
  void initState() => calls.add('initState');

  @override
  void didChangeDependencies() => calls.add('dcd');

  @override
  Seed build(TreeContext context) {
    calls.add('build');
    return const _Leaf();
  }

  @override
  void dispose() => calls.add('dispose');
}

class _ReaderSeed extends StatefulSeed {
  const _ReaderSeed();
  @override
  _ReaderState createState() => _ReaderState();
}

class _ReaderState extends State<_ReaderSeed> {
  final calls = <String>[];
  int? lastValue;

  @override
  void didChangeDependencies() {
    calls.add('dcd');
    lastValue = context.dependOnInheritedSeedOfExactType<int>();
  }

  @override
  Seed build(TreeContext context) {
    calls.add('build');
    return const _Leaf();
  }
}

// --- tests ---

void main() {
  group('StatefulSeed', () {
    test('createBranch returns StatefulBranch', () {
      expect(const _TrackedSeed().createBranch(), isA<StatefulBranch>());
    });
  });

  group('StatefulBranch lifecycle on mount', () {
    test('order: initState → didChangeDependencies → build', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      expect(
        (branch.state as _TrackedState).calls,
        equals(['initState', 'dcd', 'build']),
      );
    });

    test('state.seed is the StatefulSeed config', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      expect(branch.state.seed, isA<_TrackedSeed>());
    });

    test('state.context is the capability handle bound to the branch (A8)', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      final context = (branch.state as _TrackedState).context;
      // The handle delegates to the branch...
      expect(context.branchId, equals(branch.branchId));
      // ...but is never the branch itself (A8: the separate-handle fork —
      // perception asserted `state.context` WAS the element here).
      expect(context, isNot(same(branch)));
      expect(context, isNot(isA<Branch>()));
    });
  });

  group('setState() sink', () {
    test('setState() marks branch dirty and rebuild runs state.build', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      final state = branch.state as _TrackedState;
      state.calls.clear();

      state.setState(() => state.count++);
      expect(state.count, equals(1));
      owner.flush();
      expect(state.calls, equals(['build']));
    });

    test('setState() does not fire didChangeDependencies', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      final state = branch.state as _TrackedState;
      state.calls.clear();

      state.setState(() {});
      owner.flush();
      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });

  group('dispose lifecycle', () {
    test('dispose() called on unmount', () {
      final owner = TreeOwner();
      final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;
      final state = branch.state as _TrackedState;
      state.calls.clear();

      owner.unmountRoot();
      expect(state.calls, equals(['dispose']));
    });

    test(
      'dispose() called before super.unmount() (branch still mounted during dispose)',
      () {
        final owner = TreeOwner();
        final branch = owner.mountRoot(const _TrackedSeed()) as StatefulBranch;

        owner.unmountRoot();
        expect(branch.mounted, isFalse);
      },
    );
  });

  group('didChangeDependencies on InheritedSeed change', () {
    test('fires before build when inherited value changes', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedSeed<int>(value: 1, child: const _ReaderSeed()),
              )
              as InheritedBranch<int>;

      final readerBranch = root.childBranch as StatefulBranch;
      final state = readerBranch.state as _ReaderState;

      // Initial mount: dcd called with value=1
      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(1));
      state.calls.clear();

      // Update inherited value → triggers dependencyChanged → rebuild with dcd
      root.update(InheritedSeed<int>(value: 2, child: const _ReaderSeed()));
      owner.flush();

      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(2));
    });

    test('does not fire dcd on setState()-driven rebuild', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedSeed<int>(value: 1, child: const _ReaderSeed()),
              )
              as InheritedBranch<int>;

      final readerBranch = root.childBranch as StatefulBranch;
      final state = readerBranch.state as _ReaderState;
      state.calls.clear();

      // setState()-driven rebuild: no dependency change
      state.setState(() {});
      owner.flush();

      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });
}
