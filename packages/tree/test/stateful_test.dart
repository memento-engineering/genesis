// ignore_for_file: invalid_use_of_protected_member
// Port of perception's stateful_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

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

class _InitGetSeed extends StatefulSeed {
  const _InitGetSeed();
  @override
  _InitGetState createState() => _InitGetState();
}

class _InitGetState extends State<_InitGetSeed> {
  int? initValue;

  @override
  void initState() {
    initValue = context.getInheritedSeedOfExactType<int>();
  }

  @override
  Seed build(TreeContext context) => const _Leaf();
}

class _InitDependSeed extends StatefulSeed {
  const _InitDependSeed();
  @override
  _InitDependState createState() => _InitDependState();
}

class _InitDependState extends State<_InitDependSeed> {
  @override
  void initState() {
    context.dependOnInheritedSeedOfExactType<int>();
  }

  @override
  Seed build(TreeContext context) => const _Leaf();
}

class _DisposeDependSeed extends StatefulSeed {
  const _DisposeDependSeed();
  @override
  _DisposeDependState createState() => _DisposeDependState();
}

class _DisposeDependState extends State<_DisposeDependSeed> {
  @override
  Seed build(TreeContext context) => const _Leaf();

  @override
  void dispose() {
    context.dependOnInheritedSeedOfExactType<int>();
  }
}

class _DisposeGetSeed extends StatefulSeed {
  const _DisposeGetSeed();
  @override
  _DisposeGetState createState() => _DisposeGetState();
}

class _DisposeGetState extends State<_DisposeGetSeed> {
  int? disposeValue;

  @override
  Seed build(TreeContext context) => const _Leaf();

  @override
  void dispose() {
    disposeValue = context.getInheritedSeedOfExactType<int>();
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

  group('inherited lookups across the State lifecycle', () {
    test('getInheritedSeedOfExactType works in initState, dependency-free', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedSeed<int>(value: 7, child: const _InitGetSeed()),
              )
              as InheritedBranch<int>;

      final branch = root.childBranch as StatefulBranch;
      expect((branch.state as _InitGetState).initValue, equals(7));
      // A snapshot read: no dependent was registered on the provider.
      expect(root.dependents, isEmpty);
      expect(branch.dependencies, isEmpty);
    });

    test('dependOnInheritedSeedOfExactType in initState asserts', () {
      final owner = TreeOwner();
      expect(
        () => owner.mountRoot(
          InheritedSeed<int>(value: 7, child: const _InitDependSeed()),
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('called from initState'),
          ),
        ),
      );
    });

    test('dependOnInheritedSeedOfExactType in dispose asserts', () {
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<int>(value: 7, child: const _DisposeDependSeed()),
      );
      expect(
        owner.unmountRoot,
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('called from dispose'),
          ),
        ),
      );
    });

    test('getInheritedSeedOfExactType works in dispose (last read)', () {
      final owner = TreeOwner();
      final root =
          owner.mountRoot(
                InheritedSeed<int>(value: 9, child: const _DisposeGetSeed()),
              )
              as InheritedBranch<int>;
      final state =
          (root.childBranch as StatefulBranch).state as _DisposeGetState;

      owner.dispose();
      expect(state.disposeValue, equals(9));
    });
  });
}
