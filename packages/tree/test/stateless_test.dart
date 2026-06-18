// Port of perception's stateless_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _Leaf extends Seed {
  const _Leaf({super.key});
  @override
  Branch createBranch() => _LeafBranch(this);
}

class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
}

class _Tracker {
  int builds = 0;
  String? lastValue;
}

class _ReadingS extends StatelessSeed {
  _ReadingS(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    tracker.lastValue = context.dependOnInheritedSeedOfExactType<String>();
    return const _Leaf();
  }
}

class _SimpleS extends StatelessSeed {
  const _SimpleS({this.child = const _Leaf()});
  final Seed child;
  @override
  Seed build(TreeContext context) => child;
}

void main() {
  test('returns StatelessBranch', () {
    expect(_SimpleS().createBranch(), isA<StatelessBranch>());
  });

  group('ComponentBranch child lifecycle', () {
    late TreeOwner owner;

    setUp(() {
      owner = TreeOwner();
    });
    tearDown(() => owner.dispose());

    test('builds its child synchronously on mount (no external dirty)', () {
      // mountRoot alone must produce the subtree — Flutter's _firstBuild.
      // No markNeedsRebuild / flush required.
      final branch = owner.mountRoot(_SimpleS()) as StatelessBranch;
      expect(branch.child, isNotNull);
      expect(branch.child!.mounted, isTrue);
    });

    test('child identity preserved across a rebuild when canUpdate=true', () {
      final branch = owner.mountRoot(_SimpleS()) as StatelessBranch;
      final first = branch.child;

      branch.markNeedsRebuild();
      owner.flush();
      expect(branch.child, same(first));
    });

    test('child remounted when canUpdate=false (key change)', () {
      final branch =
          owner.mountRoot(_SimpleS(child: const _Leaf(key: ValueKey('a'))))
              as StatelessBranch;
      final oldChild = branch.child!;
      expect(oldChild.mounted, isTrue);

      // A9 delta: update() alone now re-runs build and swaps the child
      // (ADR-0001 Decision 4); the explicit markNeedsRebuild + flush is kept
      // from the perception suite but is no longer required.
      branch.update(_SimpleS(child: const _Leaf(key: ValueKey('b'))));
      branch.markNeedsRebuild();
      owner.flush();

      expect(branch.child, isNot(same(oldChild)));
      expect(oldChild.mounted, isFalse);
      expect(branch.child!.mounted, isTrue);
    });

    test('unmounts child before clearing self', () {
      final branch = owner.mountRoot(_SimpleS()) as StatelessBranch;
      final child = branch.child!;

      branch.unmount();

      expect(child.mounted, isFalse);
      expect(branch.mounted, isFalse);
    });
  });

  group('InheritedSeed + StatelessSeed headline', () {
    late TreeOwner owner;

    setUp(() {
      owner = TreeOwner();
    });
    tearDown(() => owner.dispose());

    test('reads provider on mount, re-reads after provider update', () {
      final tracker = _Tracker();
      final ipBranch =
          owner.mountRoot(
                InheritedSeed<String>(value: 'a', child: _ReadingS(tracker)),
              )
              as InheritedBranch<String>;

      // Mounting drove the first build through the whole subtree — the
      // dependency on the provider is registered and 'a' was read.
      expect(tracker.builds, 1);
      expect(tracker.lastValue, 'a');

      ipBranch.update(
        InheritedSeed<String>(value: 'b', child: _ReadingS(tracker)),
      );
      owner.flush();

      expect(tracker.builds, 2);
      expect(tracker.lastValue, 'b');
    });

    test('no dependent invalidation when provider value unchanged', () {
      final tracker = _Tracker();
      final ipBranch =
          owner.mountRoot(
                InheritedSeed<String>(value: 'a', child: _ReadingS(tracker)),
              )
              as InheritedBranch<String>;

      expect(tracker.builds, 1);

      ipBranch.update(
        InheritedSeed<String>(value: 'a', child: _ReadingS(tracker)),
      );
      // updateShouldNotify=false scheduled nothing: the flush drains empty.
      expect(owner.flush(), isEmpty);

      // A9 delta: perception expected builds == 1 here (update() swapped the
      // config without re-running builders). Under ADR-0001 Decision 4 the
      // child's config instance changed, so the update cascade re-runs
      // build() exactly once — even though updateShouldNotify is false and
      // no dependent invalidation was scheduled.
      expect(tracker.builds, 2);
    });
  });
}
