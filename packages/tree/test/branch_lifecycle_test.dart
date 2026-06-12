// Port of perception's element_lifecycle_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:tree/tree.dart';

class _S extends Seed {
  const _S({this.tag = '', super.key});
  final String tag;
  @override
  _B createBranch() => _B(this);
}

class _B extends Branch {
  _B(super.seed);
  final calls = <String>[];
  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    calls.add('mount');
  }

  @override
  void update(Seed newSeed) {
    super.update(newSeed);
    calls.add('update');
  }

  @override
  void unmount() {
    calls.add('unmount');
    super.unmount();
  }
}

void main() {
  group('Branch lifecycle', () {
    test('mount: sets mounted=true, branchId non-empty', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_S()) as _B;
      expect(branch.mounted, isTrue);
      expect(branch.branchId, isNotEmpty);
      expect(branch.calls, equals(['mount']));
    });

    test('mount: branchId is stable after update', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_S()) as _B;
      final id = branch.branchId;
      branch.update(_S(tag: 'x'));
      expect(branch.branchId, equals(id));
    });

    test('mount: throws AssertionError on double-mount', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_S()) as _B;
      expect(() => branch.mount(null, null), throwsA(isA<AssertionError>()));
    });

    test('mount: throws AssertionError when no owner is available', () {
      final branch = _B(_S());
      expect(() => branch.mount(null, null), throwsA(isA<AssertionError>()));
    });

    test('unmount: sets mounted=false', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_S()) as _B;
      branch.unmount();
      expect(branch.mounted, isFalse);
      expect(branch.calls, equals(['mount', 'unmount']));
    });

    test('unmount: throws AssertionError if already unmounted', () {
      final branch = _B(_S());
      expect(() => branch.unmount(), throwsA(isA<AssertionError>()));
    });

    test('update: replaces config, records call', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_S(tag: 'a')) as _B;
      branch.update(_S(tag: 'b'));
      expect((branch.seed as _S).tag, equals('b'));
      expect(branch.calls, equals(['mount', 'update']));
    });

    test('update: throws AssertionError if unmounted', () {
      final branch = _B(_S());
      expect(() => branch.update(_S()), throwsA(isA<AssertionError>()));
    });

    test(
      'update: throws AssertionError when canUpdate=false (key mismatch)',
      () {
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final branch = owner.mountRoot(_S(key: 'a')) as _B;
        expect(
          () => branch.update(_S(key: 'b')),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });

  group('branchId: owner-scoped issuance', () {
    test(
      'root gets id 0, child mounted via mount() inherits owner and gets id 1',
      () {
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(_S()) as _B;
        final child = _B(_S())..mount(root, 0);
        expect(root.branchId, equals('0'));
        expect(child.branchId, equals('1'));
      },
    );

    test('two owners issue independent id sequences (both roots get id 0)', () {
      final owner1 = TreeOwner();
      final owner2 = TreeOwner();
      addTearDown(owner1.dispose);
      addTearDown(owner2.dispose);
      final branch1 = owner1.mountRoot(_S()) as _B;
      final branch2 = owner2.mountRoot(_S()) as _B;
      expect(branch1.branchId, equals('0'));
      expect(branch2.branchId, equals('0'));
    });
  });

  group('updateChild (single-child reconciliation)', () {
    late TreeOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    test('null seed: unmounts child and returns null', () {
      final child = _B(_S())..mount(root, 0);
      expect(root.updateChild(child, null, 0), isNull);
      expect(child.mounted, isFalse);
      expect(child.calls, containsAllInOrder(['mount', 'unmount']));
    });

    test('null child: mounts fresh branch', () {
      final result = root.updateChild(null, _S(tag: 'new'), 0);
      expect(result, isNotNull);
      expect(result!.mounted, isTrue);
    });

    test(
      'canUpdate=true: updates in place, same object, branchId preserved',
      () {
        final child = _B(_S(tag: 'a'))..mount(root, 0);
        final oldId = child.branchId;
        final result = root.updateChild(child, _S(tag: 'b'), 0);
        expect(result, same(child));
        expect(result!.branchId, equals(oldId));
        expect(child.calls, equals(['mount', 'update']));
      },
    );

    test('canUpdate=false (key mismatch): unmounts old, mounts new', () {
      final child = _S(key: 'x').createBranch()..mount(root, 0);
      final result = root.updateChild(child, _S(key: 'y'), 0);
      expect(result, isNot(same(child)));
      expect(child.mounted, isFalse);
      expect(result!.mounted, isTrue);
    });
  });

  group('updateChildren (multi-child keyed reconciliation)', () {
    late TreeOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = TreeOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    List<_B> mountAll(List<Seed> seeds) {
      return seeds.indexed
          .map((r) => seeds[r.$1].createBranch() as _B..mount(root, r.$1))
          .toList();
    }

    test('keyed reorder preserves branch identity (fork #2)', () {
      final branches = mountAll([
        _S(tag: 'a', key: 'k-a'),
        _S(tag: 'b', key: 'k-b'),
        _S(tag: 'c', key: 'k-c'),
      ]);
      final ids = branches.map((b) => b.branchId).toList();

      final result = root.updateChildren(branches, [
        _S(tag: 'c2', key: 'k-c'),
        _S(tag: 'a2', key: 'k-a'),
        _S(tag: 'b2', key: 'k-b'),
      ]);

      expect(result[0].branchId, equals(ids[2])); // c reused
      expect(result[1].branchId, equals(ids[0])); // a reused
      expect(result[2].branchId, equals(ids[1])); // b reused
      expect(result.every((b) => b.mounted), isTrue);
    });

    test('unmatched key: old unmounted, new branch mounted', () {
      final branches = mountAll([_S(key: 'k-a'), _S(key: 'k-b')]);
      final result = root.updateChildren(branches, [
        _S(key: 'k-a'),
        _S(key: 'k-c'),
      ]);

      expect(result[0], same(branches[0]));
      expect(result[1], isNot(same(branches[1])));
      expect(branches[1].mounted, isFalse);
      expect(result[1].mounted, isTrue);
    });

    test('shorter new list: extra old branches are unmounted', () {
      final branches = mountAll([_S(key: 'k-a'), _S(key: 'k-b')]);
      final result = root.updateChildren(branches, [_S(key: 'k-a')]);

      expect(result.length, equals(1));
      expect(result[0], same(branches[0]));
      expect(branches[1].mounted, isFalse);
    });

    test('longer new list: extra seeds are mounted fresh', () {
      final branches = mountAll([_S(key: 'k-a')]);
      final result = root.updateChildren(branches, [
        _S(key: 'k-a'),
        _S(key: 'k-b'),
      ]);

      expect(result.length, equals(2));
      expect(result[0], same(branches[0]));
      expect(result[1].mounted, isTrue);
    });

    test('unkeyed: branches updated positionally when types match', () {
      final branches = mountAll([_S(tag: 'a'), _S(tag: 'b')]);
      final ids = branches.map((b) => b.branchId).toList();

      final result = root.updateChildren(branches, [
        _S(tag: 'a2'),
        _S(tag: 'b2'),
      ]);

      expect(result[0].branchId, equals(ids[0]));
      expect(result[1].branchId, equals(ids[1]));
    });
  });
}
