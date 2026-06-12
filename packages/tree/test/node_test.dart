// Port of perception's node_test.dart to tree vocabulary.
//
// Node/NodeBranch live in test/src/fixtures.dart, NOT in lib/: tree core is
// artifact-agnostic (ADR-0001 Decision 3), so the keyed multichild container
// primitive belongs to domains; tests use the fixture analog.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

void main() {
  group('Node construction', () {
    test('createBranch returns NodeBranch', () {
      expect(const Node('n').createBranch(), isA<NodeBranch>());
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

  group('NodeBranch mount', () {
    test('empty node mounts with no children', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch = owner.mountRoot(const Node('root')) as NodeBranch;
      expect(branch.mounted, isTrue);
      expect(branch.children, isEmpty);
    });

    test('children are mounted on root mount', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeBranch;
      expect(branch.children.length, equals(2));
      expect(branch.children.every((c) => c.mounted), isTrue);
    });

    test('children receive distinct branchIds', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeBranch;
      expect(branch.children[0].branchId, isNotEmpty);
      expect(
        branch.children[0].branchId,
        isNot(equals(branch.children[1].branchId)),
      );
    });
  });

  group('NodeBranch update — keyed identity', () {
    test('keyed child identity preserved after reorder', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const Leaf('a', key: 'ka'),
                    const Leaf('b', key: 'kb'),
                  ],
                ),
              )
              as NodeBranch;

      final idA = branch.children[0].branchId;
      final idB = branch.children[1].branchId;

      branch.update(
        Node(
          'root',
          children: [
            const Leaf('b', key: 'kb'),
            const Leaf('a', key: 'ka'),
          ],
        ),
      );

      expect(branch.children[0].branchId, equals(idB));
      expect(branch.children[1].branchId, equals(idA));
      expect(branch.children.every((c) => c.mounted), isTrue);
    });

    test('removed keyed child is unmounted', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const Leaf('a', key: 'ka'),
                    const Leaf('b', key: 'kb'),
                  ],
                ),
              )
              as NodeBranch;

      final removed = branch.children[1];
      branch.update(Node('root', children: [const Leaf('a', key: 'ka')]));

      expect(branch.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });

    test('new keyed child is freshly mounted', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(Node('root', children: [const Leaf('a', key: 'ka')]))
              as NodeBranch;

      branch.update(
        Node(
          'root',
          children: [
            const Leaf('a', key: 'ka'),
            const Leaf('b', key: 'kb'),
          ],
        ),
      );

      expect(branch.children.length, equals(2));
      expect(branch.children[1].mounted, isTrue);
      expect(branch.children[1].branchId, isNotEmpty);
    });
  });

  group('NodeBranch update — unkeyed identity', () {
    test('unkeyed positional identity preserved across update', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeBranch;

      final id0 = branch.children[0].branchId;
      final id1 = branch.children[1].branchId;

      branch.update(Node('root', children: [const Leaf('x'), const Leaf('y')]));

      expect(branch.children[0].branchId, equals(id0));
      expect(branch.children[1].branchId, equals(id1));
    });

    test('unkeyed excess child at tail is unmounted', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final branch =
          owner.mountRoot(
                Node('root', children: [const Leaf('a'), const Leaf('b')]),
              )
              as NodeBranch;

      final removed = branch.children[1];
      branch.update(Node('root', children: [const Leaf('a')]));

      expect(branch.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });
  });

  group('NodeBranch unmount', () {
    test('all children unmounted when node unmounts', () {
      final owner = TreeOwner();
      final branch =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const Leaf('a', key: 'ka'),
                    const Leaf('b', key: 'kb'),
                  ],
                ),
              )
              as NodeBranch;
      final c0 = branch.children[0];
      final c1 = branch.children[1];

      owner.unmountRoot();

      expect(c0.mounted, isFalse);
      expect(c1.mounted, isFalse);
    });
  });
}
