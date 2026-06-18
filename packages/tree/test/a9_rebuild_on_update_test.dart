// ignore_for_file: invalid_use_of_protected_member
// A9 (ADR-0001 Decision 4): a same-type+key config update invokes the rebuild
// hook. The composition layer defines the hook as re-running build(); a
// non-component branch keeps its own artifact response and gains no build
// semantics. This deliberately diverges from perception, where update() only
// swapped the config.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _Tracker {
  int builds = 0;
  String? lastLabel;
}

class _CountedSeed extends StatelessSeed {
  const _CountedSeed(this.tracker, {this.label = '', super.key});
  final _Tracker tracker;
  final String label;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    tracker.lastLabel = label;
    return const Leaf('counted-child');
  }
}

class _WrapperSeed extends StatelessSeed {
  const _WrapperSeed(this.tracker, {this.label = ''});
  final _Tracker tracker;
  final String label;
  @override
  Seed build(TreeContext context) =>
      _CountedSeed(tracker, label: label, key: ValueKey('inner'));
}

class _LabelSeed extends StatefulSeed {
  const _LabelSeed(this.label);
  final String label;
  @override
  _LabelState createState() => _LabelState();
}

class _LabelState extends State<_LabelSeed> {
  int builds = 0;
  String? lastBuiltLabel;
  @override
  Seed build(TreeContext context) {
    builds++;
    lastBuiltLabel = seed.label;
    return const Leaf('label-child');
  }
}

class _HookSeed extends Seed {
  const _HookSeed({this.tag = ''});
  final String tag;
  @override
  _HookBranch createBranch() => _HookBranch(this);
}

class _HookBranch extends Branch {
  _HookBranch(_HookSeed super.seed);
  int hookRuns = 0;
  @override
  void performRebuild() {
    hookRuns++;
  }
}

void main() {
  group('A9: component branches re-run build() on config update', () {
    test('same-type+key update re-runs StatelessBranch.build — no flush, '
        'no markNeedsRebuild', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final branch =
          owner.mountRoot(_CountedSeed(tracker, label: 'a', key: ValueKey('k')))
              as StatelessBranch;
      expect(tracker.builds, 1);
      expect(tracker.lastLabel, 'a');

      branch.update(_CountedSeed(tracker, label: 'b', key: ValueKey('k')));

      // The builder re-ran synchronously with the new config in place.
      expect(tracker.builds, 2);
      expect(tracker.lastLabel, 'b');
    });

    test('stateful config change is visible without external dirtying '
        '(the spike-5 gap, closed)', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const _LabelSeed('old')) as StatefulBranch;
      final state = branch.state as _LabelState;
      expect(state.lastBuiltLabel, 'old');

      branch.update(const _LabelSeed('new'));

      expect(state.builds, 2);
      expect(state.lastBuiltLabel, 'new');
    });

    test('update cascades through reconcile: parent rebuild re-runs the '
        'child builder with the new prop', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent =
          owner.mountRoot(_WrapperSeed(tracker, label: 'one'))
              as StatelessBranch;
      expect(tracker.builds, 1);
      final innerBranch = parent.child;

      parent.update(_WrapperSeed(tracker, label: 'two'));

      // Same type + key 'inner': identity preserved, builder re-ran with the
      // new prop — expression surfaces re-render on prop change with no
      // manual plumbing.
      expect(parent.child, same(innerBranch));
      expect(tracker.builds, 2);
      expect(tracker.lastLabel, 'two');
    });
  });

  group('A9: non-component branches keep their own artifact response', () {
    test('update() reaches the hook on a bare branch (the core promise)', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(_HookSeed(tag: 'a')) as _HookBranch;
      expect(branch.hookRuns, 0); // bare branch: no first-build on mount

      branch.update(_HookSeed(tag: 'b'));

      expect(branch.hookRuns, 1);
      expect((branch.seed as _HookSeed).tag, 'b');
    });

    test('a bare container Node-analog does not magically gain build '
        'semantics: no build contract, its hook reconciles children', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node('root', children: [const Leaf('a', key: ValueKey('k'))]),
              )
              as NodeBranch;
      // Not a component: there is no build() to gain (compile-level — the
      // member does not exist on NodeBranch), and no ComponentBranch in its
      // type hierarchy.
      expect(branch, isNot(isA<ComponentBranch>()));

      final keptId = branch.children[0].branchId;
      branch.update(
        Node(
          'root',
          children: [
            const Leaf('b', key: ValueKey('k')),
            const Leaf('c'),
          ],
        ),
      );

      // The artifact response is keyed reconciliation, nothing more:
      // identity preserved for the matching key, new child mounted fresh.
      expect(branch.children.length, 2);
      expect(branch.children[0].branchId, keptId);
      expect(branch.children[1].mounted, isTrue);
    });

    test('a bare leaf branch under a rebuilding container runs its empty '
        'hook, not a builder', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(Node('root', children: [const Leaf('a')]))
              as NodeBranch;
      final leaf = branch.children[0] as LeafBranch;

      branch.update(Node('root', children: [const Leaf('b')]));

      // The leaf was updated in place (positional identity); its config
      // swapped and its (empty, inherited) hook ran — no build, no children.
      expect(branch.children[0], same(leaf));
      expect((leaf.seed as Leaf).tag, 'b');
      var visited = 0;
      leaf.visitChildren((_) => visited++);
      expect(visited, 0);
    });
  });
}
