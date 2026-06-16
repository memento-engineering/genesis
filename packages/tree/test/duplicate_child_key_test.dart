// The debug guard in `updateChildren`: a key identifies exactly one child of a
// parent. Two siblings sharing a key collapse silently in keyed reconcile (the
// map keeps one; a key-based lookup finds more than one), so the guard catches
// it at reconcile time with the offending key. Unkeyed siblings are positional
// and exempt.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

void main() {
  test('duplicate sibling keys trip the guard at mount, naming the key', () {
    final owner = TreeOwner();
    expect(
      () => owner.mountRoot(
        const Node(
          'parent',
          children: [
            Leaf('a', key: 'dup'),
            Leaf('b', key: 'dup'),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('Duplicate child key'), contains('dup')),
        ),
      ),
    );
  });

  test('distinct keys and multiple unkeyed siblings reconcile fine', () {
    final root =
        TreeOwner().mountRoot(
              const Node(
                'parent',
                children: [
                  Leaf('a', key: 'k1'),
                  Leaf('b', key: 'k2'),
                  Leaf('c'), // unkeyed — positional, no collision
                  Leaf('d'), // unkeyed
                ],
              ),
            )
            as NodeBranch;
    expect(root.children.length, 4);
  });

  test('an update that introduces a duplicate key also trips the guard', () {
    final root =
        TreeOwner().mountRoot(
              const Node('parent', children: [Leaf('a', key: 'k1')]),
            )
            as NodeBranch;
    expect(
      () => root.update(
        const Node(
          'parent',
          children: [
            Leaf('a', key: 'x'),
            Leaf('b', key: 'x'),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
