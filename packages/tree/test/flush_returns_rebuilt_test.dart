// ADR-0001 Decision 5 obligation (spike 4): BuildOwner.flush() returns the
// drained dirty set — the elements this call actually rebuilt, in flush
// (depth) order — so render backends can map dirty regions without faking it
// in builders.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _HookComponent extends Component {
  const _HookComponent();
  @override
  _HookElement createElement() => _HookElement(this);
}

class _HookElement extends Element {
  _HookElement(super.component);
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

class _CountedComponent extends StatelessComponent {
  const _CountedComponent(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    return const Leaf('counted-child');
  }
}

class _WrapperComponent extends StatelessComponent {
  const _WrapperComponent(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) => _CountedComponent(tracker);
}

void main() {
  group('flush() return value', () {
    test('returns an empty list when nothing is dirty', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(const _HookComponent());
      expect(owner.flush(), isEmpty);
    });

    test('returns exactly the rebuilt elements, in depth order regardless '
        'of scheduling order', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookComponent()) as _HookElement;
      final mid = _HookElement(const _HookComponent())..mount(root, 0);
      final leaf = _HookElement(const _HookComponent())..mount(mid, 0);

      // Schedule deepest-first to prove the drain re-orders by depth.
      leaf.markNeedsRebuild();
      mid.markNeedsRebuild();
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(rebuilt, equals(<Element>[root, mid, leaf]));
      expect(root.hookRuns, 1);
      expect(mid.hookRuns, 1);
      expect(leaf.hookRuns, 1);
    });

    test('a element dirtied mid-flush is rebuilt in the same pass and '
        'appears in the drained list', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookComponent()) as _HookElement;
      final target = _HookElement(const _HookComponent())..mount(root, 0);

      root.sideEffect = () => target.markNeedsRebuild();
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(rebuilt, equals(<Element>[root, target]));
      expect(target.hookRuns, 1);
    });

    test('a element unmounted after scheduling is drained but excluded — '
        'backends never receive dead elements', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookComponent()) as _HookElement;
      final doomed = _HookElement(const _HookComponent())..mount(root, 0);

      doomed.markNeedsRebuild();
      doomed.unmount();

      final rebuilt = owner.flush();

      expect(rebuilt, isEmpty);
      expect(doomed.hookRuns, 0);
    });

    test('a element force-rebuilt by an update cascade before the drain is '
        'excluded — it was not rebuilt by this flush call', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent =
          owner.mountRoot(_WrapperComponent(tracker)) as StatelessElement;
      final child = parent.child! as StatelessElement;
      expect(tracker.builds, 1);

      child.markNeedsRebuild(); // scheduled with the owner
      // A9 cascade: the parent's update re-runs its build, reconciles the
      // child in place, and force-rebuilds it — clearing its dirty flag.
      parent.update(_WrapperComponent(tracker));
      expect(tracker.builds, 2);

      final rebuilt = owner.flush();

      expect(
        rebuilt,
        isEmpty,
        reason:
            'the drained element was already clean — it rebuilt during '
            'the update cascade, not during this flush',
      );
      expect(tracker.builds, 2); // and the drain rebuilt nothing extra
    });

    test('successive flushes each return their own drained list', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _HookComponent()) as _HookElement;

      root.markNeedsRebuild();
      expect(owner.flush(), equals(<Element>[root]));
      expect(owner.flush(), isEmpty);

      root.markNeedsRebuild();
      expect(owner.flush(), equals(<Element>[root]));
    });
  });
}
