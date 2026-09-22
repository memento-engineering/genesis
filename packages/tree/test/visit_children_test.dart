// ADR-0001 Decision 5 obligation: Element carries a real traversal contract —
// visitChildren over direct children — replacing the spike-era practice of
// dispatching on concrete element shapes via test-only getters.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _WrapperComponent extends StatelessComponent {
  const _WrapperComponent(this.child);
  final Component child;
  @override
  Component build(BuildContext context) => child;
}

class _StatefulWrapperComponent extends StatefulComponent {
  const _StatefulWrapperComponent(this.child);
  final Component child;
  @override
  _StatefulWrapperState createState() => _StatefulWrapperState();
}

class _StatefulWrapperState extends State<_StatefulWrapperComponent> {
  @override
  Component build(BuildContext context) => component.child;
}

List<Element> _directChildren(Element element) {
  final children = <Element>[];
  element.visitChildren(children.add);
  return children;
}

void main() {
  group('visitChildren — per-kind contracts', () {
    late BuildOwner owner;
    setUp(() => owner = BuildOwner());
    tearDown(() => owner.dispose());

    test('bare leaf element visits nothing (base implementation)', () {
      final root = owner.mountRoot(const Leaf('only'));
      expect(_directChildren(root), isEmpty);
    });

    test('NodeElement visits its direct children, in tree order', () {
      final root = owner.mountRoot(
        Node(
          'root',
          children: [const Leaf('a'), const Leaf('b'), const Leaf('c')],
        ),
      );
      final children = _directChildren(root);
      expect(children.length, 3);
      expect(
        children.map((b) => (b.component as Leaf).tag).toList(),
        equals(['a', 'b', 'c']),
      );
    });

    test('BuildableElement (stateless) visits its single built child', () {
      final root = owner.mountRoot(const _WrapperComponent(Leaf('inner')));
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.component as Leaf).tag, 'inner');
    });

    test('BuildableElement (stateful) visits its single built child', () {
      final root = owner.mountRoot(
        const _StatefulWrapperComponent(Leaf('inner')),
      );
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.component as Leaf).tag, 'inner');
    });

    test('InheritedElement visits its child', () {
      final root = owner.mountRoot(
        InheritedComponent<String>(value: 'v', child: const Leaf('inner')),
      );
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.component as Leaf).tag, 'inner');
    });

    test('visitChildren reflects reconciled children after update', () {
      final root =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const Leaf('a', key: ValueKey('ka')),
                    const Leaf('b', key: ValueKey('kb')),
                  ],
                ),
              )
              as NodeElement;
      root.update(
        Node('root', children: [const Leaf('b', key: ValueKey('kb'))]),
      );
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.component as Leaf).tag, 'b');
    });
  });

  group('visitChildren — recursive traversal (the spike-5 consumer shape)', () {
    test('a fresh walk from the root reaches every mounted element and '
        'resolves ids without holding element references', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const _WrapperComponent(Leaf('w-inner')),
                    InheritedComponent<String>(
                      value: 'v',
                      child: const _StatefulWrapperComponent(Leaf('s-inner')),
                    ),
                    const Leaf('plain', key: ValueKey('kp')),
                  ],
                ),
              )
              as NodeElement;

      Element? findById(String id) {
        Element? found;
        void walk(Element element) {
          if (found != null) return;
          if (element.elementId == id) {
            found = element;
            return;
          }
          element.visitChildren(walk);
        }

        walk(root);
        return found;
      }

      // Hit-test fresh against the live tree: resolve a leaf by id.
      final target = root.children[2];
      expect(findById(target.elementId), same(target));

      // Count the whole tree: root + 3 children + wrapper child +
      // inherited child + stateful child = 7.
      var count = 0;
      void countWalk(Element element) {
        count++;
        element.visitChildren(countWalk);
      }

      countWalk(root);
      expect(count, 7);

      // After a re-emission drops the keyed leaf, a fresh walk no longer
      // resolves it — "the projection moved under the actor" is detectable.
      final staleId = target.elementId;
      root.update(
        Node(
          'root',
          children: [
            const _WrapperComponent(Leaf('w-inner')),
            InheritedComponent<String>(
              value: 'v',
              child: const _StatefulWrapperComponent(Leaf('s-inner')),
            ),
          ],
        ),
      );
      expect(findById(staleId), isNull);
      expect(target.mounted, isFalse);
    });
  });
}
