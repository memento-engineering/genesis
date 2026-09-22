// ignore_for_file: invalid_use_of_protected_member
// A same-type+key component update invokes the rebuild
// hook. The composition layer defines the hook as re-running build(); a
// non-component element keeps its own artifact response and gains no build
// semantics. This deliberately diverges from perception, where update() only
// swapped the config.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _Tracker {
  int builds = 0;
  String? lastLabel;
}

class _CountedComponent extends StatelessComponent {
  const _CountedComponent(this.tracker, {this.label = '', super.key});
  final _Tracker tracker;
  final String label;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    tracker.lastLabel = label;
    return const Leaf('counted-child');
  }
}

class _WrapperComponent extends StatelessComponent {
  const _WrapperComponent(this.tracker, {this.label = ''});
  final _Tracker tracker;
  final String label;
  @override
  Component build(BuildContext context) =>
      _CountedComponent(tracker, label: label, key: ValueKey('inner'));
}

class _LabelComponent extends StatefulComponent {
  const _LabelComponent(this.label);
  final String label;
  @override
  _LabelState createState() => _LabelState();
}

class _LabelState extends State<_LabelComponent> {
  int builds = 0;
  String? lastBuiltLabel;
  @override
  Component build(BuildContext context) {
    builds++;
    lastBuiltLabel = component.label;
    return const Leaf('label-child');
  }
}

class _HookComponent extends Component {
  const _HookComponent({this.tag = ''});
  final String tag;
  @override
  _HookElement createElement() => _HookElement(this);
}

class _HookElement extends Element {
  _HookElement(_HookComponent super.component);
  int hookRuns = 0;
  @override
  void performRebuild() {
    hookRuns++;
  }
}

void main() {
  group('A9: component elements re-run build() on config update', () {
    test('same-type+key update re-runs StatelessElement.build — no flush, '
        'no markNeedsRebuild', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final element =
          owner.mountRoot(
                _CountedComponent(tracker, label: 'a', key: ValueKey('k')),
              )
              as StatelessElement;
      expect(tracker.builds, 1);
      expect(tracker.lastLabel, 'a');

      element.update(
        _CountedComponent(tracker, label: 'b', key: ValueKey('k')),
      );

      // The builder re-ran synchronously with the new config in place.
      expect(tracker.builds, 2);
      expect(tracker.lastLabel, 'b');
    });

    test('stateful config change is visible without external dirtying '
        '(the spike-5 gap, closed)', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(const _LabelComponent('old')) as StatefulElement;
      final state = element.state as _LabelState;
      expect(state.lastBuiltLabel, 'old');

      element.update(const _LabelComponent('new'));

      expect(state.builds, 2);
      expect(state.lastBuiltLabel, 'new');
    });

    test('update cascades through reconcile: parent rebuild re-runs the '
        'child builder with the new prop', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent =
          owner.mountRoot(_WrapperComponent(tracker, label: 'one'))
              as StatelessElement;
      expect(tracker.builds, 1);
      final innerElement = parent.child;

      parent.update(_WrapperComponent(tracker, label: 'two'));

      // Same type + key 'inner': identity preserved, builder re-ran with the
      // new prop — expression surfaces re-render on prop change with no
      // manual plumbing.
      expect(parent.child, same(innerElement));
      expect(tracker.builds, 2);
      expect(tracker.lastLabel, 'two');
    });
  });

  group('A9: non-component elements keep their own artifact response', () {
    test('update() reaches the hook on a bare element (the core promise)', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_HookComponent(tag: 'a')) as _HookElement;
      expect(element.hookRuns, 0); // bare element: no first-build on mount

      element.update(_HookComponent(tag: 'b'));

      expect(element.hookRuns, 1);
      expect((element.component as _HookComponent).tag, 'b');
    });

    test('a bare container Node-analog does not magically gain build '
        'semantics: no build contract, its hook reconciles children', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a', key: ValueKey('k'))]),
              )
              as NodeElement;
      // Not a component: there is no build() to gain (compile-level — the
      // member does not exist on NodeElement), and no BuildableElement in its
      // type hierarchy.
      expect(element, isNot(isA<BuildableElement>()));

      final keptId = element.children[0].elementId;
      element.update(
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
      expect(element.children.length, 2);
      expect(element.children[0].elementId, keptId);
      expect(element.children[1].mounted, isTrue);
    });

    test('a bare leaf element under a rebuilding container runs its empty '
        'hook, not a builder', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(Node('root', children: [const Leaf('a')]))
              as NodeElement;
      final leaf = element.children[0] as LeafElement;

      element.update(Node('root', children: [const Leaf('b')]));

      // The leaf was updated in place (positional identity); its config
      // swapped and its (empty, inherited) hook ran — no build, no children.
      expect(element.children[0], same(leaf));
      expect((leaf.component as Leaf).tag, 'b');
      var visited = 0;
      leaf.visitChildren((_) => visited++);
      expect(visited, 0);
    });
  });
}
