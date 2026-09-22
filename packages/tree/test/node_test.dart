// Port of perception's node_test.dart to tree vocabulary.
//
// Node/NodeElement live in test/src/fixtures.dart, NOT in lib/: tree core is
// artifact-agnostic (ADR-0001 Decision 3), so the keyed multichild container
// primitive belongs to domains; tests use the fixture analog.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

void main() {
  group('Node construction', () {
    test('createElement returns NodeElement', () {
      expect(const Node('n').createElement(), isA<NodeElement>());
    });

    test('name and children stored', () {
      const c = Leaf('x');
      final n = Node('root', children: [c]);
      expect(n.name, equals('root'));
      expect(n.children, equals([c]));
    });

    test('default children is empty', () {
      expect(const Node('n').children, isEmpty);
    });
  });

  group('NodeElement mount', () {
    test('empty node mounts with no children', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(const Node('root')) as NodeElement;
      expect(element.mounted, isTrue);
      expect(element.children, isEmpty);
    });

    test('children are mounted on root mount', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeElement;
      expect(element.children.length, equals(2));
      expect(element.children.every((c) => c.mounted), isTrue);
    });

    test('children receive distinct elementIds', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeElement;
      expect(element.children[0].elementId, isNotEmpty);
      expect(
        element.children[0].elementId,
        isNot(equals(element.children[1].elementId)),
      );
    });
  });

  group('NodeElement update — keyed identity', () {
    test('keyed child identity preserved after reorder', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
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

      final idA = element.children[0].elementId;
      final idB = element.children[1].elementId;

      element.update(
        Node(
          'root',
          children: [
            const Leaf('b', key: ValueKey('kb')),
            const Leaf('a', key: ValueKey('ka')),
          ],
        ),
      );

      expect(element.children[0].elementId, equals(idB));
      expect(element.children[1].elementId, equals(idA));
      expect(element.children.every((c) => c.mounted), isTrue);
    });

    test('removed keyed child is unmounted', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
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

      final removed = element.children[1];
      element.update(
        Node('root', children: [const Leaf('a', key: ValueKey('ka'))]),
      );

      expect(element.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });

    test('new keyed child is freshly mounted', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a', key: ValueKey('ka'))]),
              )
              as NodeElement;

      element.update(
        Node(
          'root',
          children: [
            const Leaf('a', key: ValueKey('ka')),
            const Leaf('b', key: ValueKey('kb')),
          ],
        ),
      );

      expect(element.children.length, equals(2));
      expect(element.children[1].mounted, isTrue);
      expect(element.children[1].elementId, isNotEmpty);
    });
  });

  group('NodeElement update — unkeyed identity', () {
    test('unkeyed positional identity preserved across update', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeElement;

      final id0 = element.children[0].elementId;
      final id1 = element.children[1].elementId;

      element.update(
        Node('root', children: [const Leaf('x'), const Leaf('y')]),
      );

      expect(element.children[0].elementId, equals(id0));
      expect(element.children[1].elementId, equals(id1));
    });

    test('unkeyed excess child at tail is unmounted', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeElement;

      final removed = element.children[1];
      element.update(Node('root', children: [const Leaf('a')]));

      expect(element.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });
  });

  group('NodeElement unmount', () {
    test('all children unmounted when node unmounts', () {
      final owner = BuildOwner();
      final element =
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
      final c0 = element.children[0];
      final c1 = element.children[1];

      owner.unmountRoot();

      expect(c0.mounted, isFalse);
      expect(c1.mounted, isFalse);
    });
  });
}
