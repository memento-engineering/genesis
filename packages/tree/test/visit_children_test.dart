// ADR-0001 Decision 5 obligation: Branch carries a real traversal contract —
// visitChildren over direct children — replacing the spike-era practice of
// dispatching on concrete element shapes via test-only getters.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _WrapperSeed extends StatelessSeed {
  const _WrapperSeed(this.child);
  final Seed child;
  @override
  Seed build(TreeContext context) => child;
}

class _StatefulWrapperSeed extends StatefulSeed {
  const _StatefulWrapperSeed(this.child);
  final Seed child;
  @override
  _StatefulWrapperState createState() => _StatefulWrapperState();
}

class _StatefulWrapperState extends State<_StatefulWrapperSeed> {
  @override
  Seed build(TreeContext context) => seed.child;
}

List<Branch> _directChildren(Branch branch) {
  final children = <Branch>[];
  branch.visitChildren(children.add);
  return children;
}

void main() {
  group('visitChildren — per-kind contracts', () {
    late TreeOwner owner;
    setUp(() => owner = TreeOwner());
    tearDown(() => owner.dispose());

    test('bare leaf branch visits nothing (base implementation)', () {
      final root = owner.mountRoot(const Leaf('only'));
      expect(_directChildren(root), isEmpty);
    });

    test('NodeBranch visits its direct children, in tree order', () {
      final root = owner.mountRoot(
        Node(
          'root',
          children: [const Leaf('a'), const Leaf('b'), const Leaf('c')],
        ),
      );
      final children = _directChildren(root);
      expect(children.length, 3);
      expect(
        children.map((b) => (b.seed as Leaf).tag).toList(),
        equals(['a', 'b', 'c']),
      );
    });

    test('ComponentBranch (stateless) visits its single built child', () {
      final root = owner.mountRoot(const _WrapperSeed(Leaf('inner')));
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.seed as Leaf).tag, 'inner');
    });

    test('ComponentBranch (stateful) visits its single built child', () {
      final root = owner.mountRoot(const _StatefulWrapperSeed(Leaf('inner')));
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.seed as Leaf).tag, 'inner');
    });

    test('InheritedBranch visits its child', () {
      final root = owner.mountRoot(
        InheritedSeed<String>(value: 'v', child: const Leaf('inner')),
      );
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.seed as Leaf).tag, 'inner');
    });

    test('visitChildren reflects reconciled children after update', () {
      final root =
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
      root.update(Node('root', children: [const Leaf('b', key: 'kb')]));
      final children = _directChildren(root);
      expect(children.length, 1);
      expect((children.single.seed as Leaf).tag, 'b');
    });
  });

  group('visitChildren — recursive traversal (the spike-5 consumer shape)', () {
    test('a fresh walk from the root reaches every mounted branch and '
        'resolves ids without holding branch references', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root =
          owner.mountRoot(
                Node(
                  'root',
                  children: [
                    const _WrapperSeed(Leaf('w-inner')),
                    InheritedSeed<String>(
                      value: 'v',
                      child: const _StatefulWrapperSeed(Leaf('s-inner')),
                    ),
                    const Leaf('plain', key: 'kp'),
                  ],
                ),
              )
              as NodeBranch;

      Branch? findById(String id) {
        Branch? found;
        void walk(Branch branch) {
          if (found != null) return;
          if (branch.branchId == id) {
            found = branch;
            return;
          }
          branch.visitChildren(walk);
        }

        walk(root);
        return found;
      }

      // Hit-test fresh against the live tree: resolve a leaf by id.
      final target = root.children[2];
      expect(findById(target.branchId), same(target));

      // Count the whole tree: root + 3 children + wrapper child +
      // inherited child + stateful child = 7.
      var count = 0;
      void countWalk(Branch branch) {
        count++;
        branch.visitChildren(countWalk);
      }

      countWalk(root);
      expect(count, 7);

      // After a re-emission drops the keyed leaf, a fresh walk no longer
      // resolves it — "the projection moved under the actor" is detectable.
      final staleId = target.branchId;
      root.update(
        Node(
          'root',
          children: [
            const _WrapperSeed(Leaf('w-inner')),
            InheritedSeed<String>(
              value: 'v',
              child: const _StatefulWrapperSeed(Leaf('s-inner')),
            ),
          ],
        ),
      );
      expect(findById(staleId), isNull);
      expect(target.mounted, isFalse);
    });
  });
}
