// ADR-0001 Decision 5 obligation (spike 4): TreeOwner.flush() returns the
// drained dirty set — the branches this call actually rebuilt, in flush
// (depth) order — so render backends can map dirty regions without faking it
// in builders.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _HookSeed extends Seed {
  const _HookSeed();
  @override
  _HookBranch createBranch() => _HookBranch(this);
}

class _HookBranch extends Branch {
  _HookBranch(super.seed);
  int hookRuns = 0;
  void Function()? sideEffect;
  @override
  void performRebuild() {
    hookRuns++;
    sideEffect?.call();
  }
}

class _Tracker {
  int builds = 0;
}

class _CountedSeed extends StatelessSeed {
  const _CountedSeed(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    return const Leaf('counted-child');
  }
}

class _WrapperSeed extends StatelessSeed {
  const _WrapperSeed(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) => _CountedSeed(tracker);
}

void main() {
  group('flush() return value', () {
    test('returns an empty list when nothing is dirty', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _HookSeed());
      expect(owner.flush(), isEmpty);
    });

    test('returns exactly the rebuilt branches, in depth order regardless '
        'of scheduling order', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookSeed()) as _HookBranch;
      final mid = _HookBranch(const _HookSeed())..mount(root, 0);
      final leaf = _HookBranch(const _HookSeed())..mount(mid, 0);

      // Schedule deepest-first to prove the drain re-orders by depth.
      leaf.markNeedsRebuild();
      mid.markNeedsRebuild();
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(rebuilt, equals(<Branch>[root, mid, leaf]));
      expect(root.hookRuns, 1);
      expect(mid.hookRuns, 1);
      expect(leaf.hookRuns, 1);
    });

    test('a branch dirtied mid-flush is rebuilt in the same pass and '
        'appears in the drained list', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookSeed()) as _HookBranch;
      final target = _HookBranch(const _HookSeed())..mount(root, 0);

      root.sideEffect = () => target.markNeedsRebuild();
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(rebuilt, equals(<Branch>[root, target]));
      expect(target.hookRuns, 1);
    });

    test('a branch unmounted after scheduling is drained but excluded — '
        'backends never receive dead branches', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookSeed()) as _HookBranch;
      final doomed = _HookBranch(const _HookSeed())..mount(root, 0);

      doomed.markNeedsRebuild();
      doomed.unmount();

      final rebuilt = owner.flush();

      expect(rebuilt, isEmpty);
      expect(doomed.hookRuns, 0);
    });

    test('a branch force-rebuilt by an update cascade before the drain is '
        'excluded — it was not rebuilt by this flush call', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(_WrapperSeed(tracker)) as StatelessBranch;
      final child = parent.child! as StatelessBranch;
      expect(tracker.builds, 1);

      child.markNeedsRebuild(); // scheduled with the owner
      // A9 cascade: the parent's update re-runs its build, reconciles the
      // child in place, and force-rebuilds it — clearing its dirty flag.
      parent.update(_WrapperSeed(tracker));
      expect(tracker.builds, 2);

      final rebuilt = owner.flush();

      expect(
        rebuilt,
        isEmpty,
        reason:
            'the drained branch was already clean — it rebuilt during '
            'the update cascade, not during this flush',
      );
      expect(tracker.builds, 2); // and the drain rebuilt nothing extra
    });

    test('successive flushes each return their own drained list', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookSeed()) as _HookBranch;

      root.markNeedsRebuild();
      expect(owner.flush(), equals(<Branch>[root]));
      expect(owner.flush(), isEmpty);

      root.markNeedsRebuild();
      expect(owner.flush(), equals(<Branch>[root]));
    });
  });
}
