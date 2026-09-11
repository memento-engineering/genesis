// Port of perception's perception_owner_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _FakeS extends Seed {
  const _FakeS({this.childConfig});
  final Seed? childConfig;
  @override
  _FakeB createBranch() => _FakeB(this);
}

class _FakeB extends Branch {
  _FakeB(_FakeS super.seed);
  int buildCount = 0;
  Branch? childBranch;

  @override
  void performRebuild() {
    buildCount++;
    final child = (seed as _FakeS).childConfig;
    childBranch = updateChild(childBranch, child, 0);
  }
}

class _RedirtyS extends Seed {
  const _RedirtyS();
  @override
  _RedirtyB createBranch() => _RedirtyB(this);
}

class _RedirtyB extends Branch {
  _RedirtyB(super.seed);

  @override
  void performRebuild() {
    markNeedsRebuild(); // pathological: re-dirty self on every rebuild
  }
}

class _ObservingS extends Seed {
  const _ObservingS();
  @override
  _ObservingB createBranch() => _ObservingB(this);
}

class _ObservingB extends Branch {
  _ObservingB(super.seed);
  int? lastValue;

  @override
  void performRebuild() {
    lastValue = dependOnInheritedSeedOfExactType<int>();
  }
}

class _CascadeSeed extends Seed {
  const _CascadeSeed();

  @override
  _CascadeBranch createBranch() => _CascadeBranch(this);
}

class _CascadeBranch extends Branch {
  _CascadeBranch(super.seed);

  final List<Branch> _children = [];
  List<Seed> nextChildSeeds = const [];
  void Function()? postReconcile;
  int buildCount = 0;

  List<Branch> get mountedChildren => List.unmodifiable(_children);

  @override
  void performRebuild() {
    buildCount++;
    final updated = updateChildren(_children, nextChildSeeds);
    _children
      ..clear()
      ..addAll(updated);
    postReconcile?.call();
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    _children.forEach(visitor);
  }

  @override
  void unmount() {
    for (final child in _children.reversed) {
      child.unmount();
    }
    _children.clear();
    super.unmount();
  }
}

void main() {
  group('TreeOwner.mountRoot', () {
    test('assigns owner to root branch before mount', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS()) as _FakeB;
      expect(root.owner, same(owner));
      expect(root.depth, 0);
      owner.dispose();
    });

    test('child mounted via updateChild inherits owner and depth=1', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS(childConfig: _FakeS())) as _FakeB;
      root.performRebuild(); // mounts child
      expect(root.childBranch?.owner, same(owner));
      expect(root.childBranch?.depth, 1);
      owner.dispose();
    });

    test('throws if mountRoot called twice', () {
      final owner = TreeOwner();
      owner.mountRoot(_FakeS());
      expect(() => owner.mountRoot(_FakeS()), throwsA(isA<AssertionError>()));
      owner.dispose();
    });
  });

  group('scheduleRebuildFor + onNeedsFlush', () {
    test('fires onNeedsFlush exactly once on empty->non-empty', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS()) as _FakeB;
      int fired = 0;
      owner.onNeedsFlush = () => fired++;

      root.markNeedsRebuild();
      root.markNeedsRebuild(); // idempotent — already dirty
      expect(fired, 1);
      owner.dispose();
    });

    test('fires again after flush empties dirty set', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS(childConfig: _FakeS())) as _FakeB;
      root.performRebuild();
      final child = root.childBranch!;
      int fired = 0;
      owner.onNeedsFlush = () => fired++;

      child.markNeedsRebuild();
      owner.flush();
      root.markNeedsRebuild();
      expect(fired, 2);
      owner.dispose();
    });
  });

  group('flush', () {
    test(
      'end-to-end: InheritedSeed value change -> rebuild reads new value',
      () {
        final owner = TreeOwner();
        final fakeS = _ObservingS();
        final root = owner.mountRoot(
          InheritedSeed<int>(value: 5, child: fakeS),
        );
        final ipBranch = root as InheritedBranch<int>;
        final fakeBranch = ipBranch.childBranch as _ObservingB;
        fakeBranch.performRebuild(); // register dependency
        root.update(InheritedSeed<int>(value: 7, child: fakeS));
        owner.flush();
        expect(fakeBranch.lastValue, 7);
        owner.dispose();
      },
    );

    test(
      'depth ordering: parent rebuilt before child, no redundant child rebuild',
      () {
        final owner = TreeOwner();
        final child = _FakeS();
        final root = owner.mountRoot(_FakeS(childConfig: child)) as _FakeB;
        root.performRebuild(); // establish child
        final childBranch = root.childBranch! as _FakeB;

        root.markNeedsRebuild();
        childBranch.markNeedsRebuild();

        final rootBuildsBefore = root.buildCount;
        final childBuildsBefore = childBranch.buildCount;
        owner.flush();
        // Root must have been rebuilt exactly once during flush
        expect(root.buildCount - rootBuildsBefore, 1);
        // Child at most once — depth ordering prevents redundant rebuild
        // (under A9, the root's reconcile force-rebuilds the child once and
        // clears its dirty flag, so the drain skips it).
        expect(
          childBranch.buildCount - childBuildsBefore,
          lessThanOrEqualTo(1),
        );
        owner.dispose();
      },
    );

    test('restored root may dirty an identical-skipped descendant', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(const _CascadeSeed()) as _CascadeBranch;
      root.nextChildSeeds = [_CascadeSeed(), _CascadeSeed()];
      root.rebuild(force: true);
      final first = root.mountedChildren[0] as _CascadeBranch;
      final target = root.mountedChildren[1] as _CascadeBranch;

      root.nextChildSeeds = [_CascadeSeed(), target.seed];
      root.postReconcile = target.markNeedsRebuild;
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(first.buildCount, 1, reason: 'the first child was force-updated');
      expect(target.buildCount, 1);
      expect(rebuilt, orderedEquals([root, target]));
      expect(root.mountedChildren.every((child) => child.mounted), isTrue);
      owner.dispose();
    });

    test('deeper cousin dirty from a later cascade sibling is rejected', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(const _CascadeSeed()) as _CascadeBranch;
      root.nextChildSeeds = [_CascadeSeed(), _CascadeSeed()];
      root.rebuild(force: true);
      final first = root.mountedChildren[0] as _CascadeBranch;
      final laterSibling = root.mountedChildren[1] as _CascadeBranch;
      first.nextChildSeeds = [_CascadeSeed()];
      first.rebuild(force: true);
      final target = first.mountedChildren.single as _CascadeBranch;

      // The depth-2 target is force-updated earlier in this same cascade. It
      // would look valid against the depth-0 drained root, but it is not a
      // descendant of the later depth-1 sibling whose build dirties it.
      first.nextChildSeeds = [_CascadeSeed()];
      laterSibling.postReconcile = target.markNeedsRebuild;
      root.nextChildSeeds = [_CascadeSeed(), _CascadeSeed()];
      root.markNeedsRebuild();

      expect(
        owner.flush,
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('branch ${target.branchId}'),
              contains('branch ${laterSibling.branchId}'),
              contains('descendant'),
              contains('may not be visited in this flush pass'),
            ),
          ),
        ),
      );
      expect(target.buildCount, 1, reason: 'already updated in this cascade');
      owner.dispose();
    });

    test(
      'pathological re-dirty: performRebuild re-dirties self throws StateError',
      () {
        final owner = TreeOwner();
        final root = owner.mountRoot(_RedirtyS());
        root.markNeedsRebuild();
        expect(() => owner.flush(), throwsA(isA<StateError>()));
        owner.dispose();
      },
    );

    test('flush is a no-op when dirty set is empty', () {
      final owner = TreeOwner();
      owner.mountRoot(_FakeS());
      expect(() => owner.flush(), returnsNormally);
      expect(owner.flush(), isEmpty);
      owner.dispose();
    });
  });

  group('dispose / unmountRoot', () {
    test('unmountRoot unmounts the root branch', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS());
      owner.unmountRoot();
      expect(root.mounted, isFalse);
    });

    test('dispose unmounts root and clears dirty set', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(_FakeS());
      root.markNeedsRebuild();
      owner.dispose();
      expect(root.mounted, isFalse);
    });
  });
}
