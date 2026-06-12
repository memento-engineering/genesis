// Port of perception's inherited_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:tree/tree.dart';

class _S extends Seed {
  const _S({this.tag = ''});
  final String tag;
  @override
  _B createBranch() => _B(this);
}

class _B extends Branch {
  _B(_S super.seed);
  bool marked = false;
  @override
  void markNeedsRebuild() {
    marked = true;
    super.markNeedsRebuild();
  }
}

InheritedBranch<String> _mountInherited(Branch parent, String value) {
  final ip = InheritedSeed<String>(value: value, child: _S());
  final branch = ip.createBranch();
  branch.mount(parent, 0);
  return branch;
}

void main() {
  group('InheritedSeed construction', () {
    test('createBranch returns InheritedBranch<T>', () {
      final ip = InheritedSeed<String>(value: 'x', child: _S());
      expect(ip.createBranch(), isA<InheritedBranch<String>>());
    });

    test('value and child are preserved', () {
      final child = _S(tag: 'c');
      final ip = InheritedSeed<int>(value: 42, child: child);
      expect(ip.value, 42);
      expect(ip.child, same(child));
    });
  });

  group('dependOnInheritedSeedOfExactType — lookup', () {
    late TreeOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    test('returns value from direct parent provider', () {
      final ip = _mountInherited(root, 'hello');
      final leaf = _B(_S())..mount(ip, 0);

      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'hello');
    });

    test('returns value from grandparent provider (O(n) walk)', () {
      final ip = _mountInherited(root, 'deep');
      final mid = _B(_S())..mount(ip, 0);
      final leaf = _B(_S())..mount(mid, 0);

      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'deep');
    });

    test('returns null when no ancestor of type T exists', () {
      final leaf = _B(_S())..mount(root, 0);
      expect(leaf.dependOnInheritedSeedOfExactType<String>(), isNull);
    });

    test('skips InheritedSeed<OtherType> and finds correct type', () {
      final intIp = InheritedSeed<int>(value: 7, child: _S());
      final intBranch = intIp.createBranch();
      intBranch.mount(root, 0);

      final strIp = InheritedSeed<String>(value: 'found', child: _S());
      final strBranch = strIp.createBranch();
      strBranch.mount(intBranch, 0);

      final leaf = _B(_S())..mount(strBranch, 0);
      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'found');
      expect(leaf.dependOnInheritedSeedOfExactType<int>(), 7);
    });
  });

  group('dependency registration', () {
    late TreeOwner testOwner;
    late _B root;
    late InheritedBranch<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
    });
    tearDown(() => testOwner.dispose());

    test('lookup registers the caller as a dependent', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(ip.dependents, contains(leaf));
    });

    test('registration is idempotent — two calls, one entry', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(ip.dependents.length, 1);
    });

    test('leaf dependencies contains the provider', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(leaf.dependencies, contains(ip));
    });
  });

  group('invalidation', () {
    late TreeOwner testOwner;
    late _B root;
    late InheritedBranch<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'old');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'value change (updateShouldNotify=true) marks dependent needsRebuild',
      () {
        expect(leaf.marked, isFalse);
        ip.update(InheritedSeed<String>(value: 'new', child: _S()));
        expect(leaf.marked, isTrue);
      },
    );

    test(
      'equal value (updateShouldNotify=false) does NOT mark needsRebuild',
      () {
        ip.update(InheritedSeed<String>(value: 'old', child: _S()));
        expect(leaf.marked, isFalse);
      },
    );

    test('custom updateShouldNotify is honoured', () {
      const nn = _NeverNotify('a');
      final nnBranch = nn.createBranch();
      nnBranch.mount(root, 1);
      final leaf2 = _B(_S())..mount(nnBranch, 0);
      leaf2.dependOnInheritedSeedOfExactType<String>();

      nnBranch.update(const _NeverNotify('b'));
      expect(leaf2.marked, isFalse);
    });
  });

  group('dependent unmount cleanup', () {
    late TreeOwner testOwner;
    late _B root;
    late InheritedBranch<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test('leaf unmount removes it from provider dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      leaf.unmount();
      expect(ip.dependents, isNot(contains(leaf)));
    });

    test('leaf unmount clears its own dependencies (no leak)', () {
      expect(leaf.dependencies, contains(ip));
      leaf.unmount();
      expect(leaf.dependencies, isEmpty);
    });
  });

  group('InheritedBranch unmount cleanup', () {
    late TreeOwner testOwner;
    late _B root;
    late InheritedBranch<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'provider unmount removes itself from dependent dependencies (no leak)',
      () {
        expect(leaf.dependencies, contains(ip));
        ip.unmount();
        expect(leaf.dependencies, isNot(contains(ip)));
      },
    );

    test('provider unmount clears its own dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      ip.unmount();
      expect(ip.dependents, isEmpty);
    });
  });

  group('Pure-Dart guard', () {
    test('InheritedBranch is a Branch', () {
      final ip = InheritedSeed<String>(value: 'x', child: _S());
      final branch = ip.createBranch();
      expect(branch, isA<Branch>());
    });
  });
}

class _NeverNotify extends InheritedSeed<String> {
  const _NeverNotify(String v) : super(value: v, child: const _S());
  @override
  bool updateShouldNotify(_) => false;
}
