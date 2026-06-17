// MultiChildSeed/MultiChildBranch — the composition-layer container that
// keyed-reconciles a config-declared List<Seed> of children (the
// MultiChildRenderObjectElement analogue). The keyed-reconcile engine itself
// (Branch.updateChildren) is proven separately via the Node test fixture; these
// tests pin the public composition-layer surface: mount-all / order,
// visitChildren, stable identity for matched children across rebuilds,
// mount-new / unmount-removed, the identical-skip fast path, the nested topology
// the_grid adopts (Grid -> Rig -> ...), and transparent composition with the
// single-child component branches.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

/// A container whose children are declared directly in config — the generic
/// composition-layer multi-child shape, here standing in for a the_grid
/// topology node.
class _Container extends MultiChildSeed {
  const _Container(List<Seed> children, {super.key})
    : super(children: children);
}

/// A second container kind — distinct `runtimeType`, so it must NOT reconcile
/// into a [_Container] even at the same slot/key.
class _OtherContainer extends MultiChildSeed {
  const _OtherContainer(List<Seed> children, {super.key})
    : super(children: children);
}

// Build counter for the identical-skip / rebuild-on-update proofs. Reset per
// test in setUp.
int _builds = 0;

/// A stateless component child that records each build — lets a test observe
/// whether a reconcile rebuilt the subtree or skipped it.
class _Counting extends StatelessSeed {
  const _Counting(this.tag, {super.key});
  final String tag;
  @override
  Seed build(TreeContext context) {
    _builds++;
    return Leaf(tag);
  }
}

// Captures the live State of the most recently mounted [_Bump] so a test can
// drive setState without reaching into the (protected) branch state.
_BumpState? _capturedBump;

/// A stateful component child whose state a test can poke via [_capturedBump].
class _Bump extends StatefulSeed {
  const _Bump({super.key});
  @override
  _BumpState createState() => _BumpState();
}

class _BumpState extends State<_Bump> {
  int n = 0;
  @override
  void initState() {
    super.initState();
    _capturedBump = this;
  }

  @override
  Seed build(TreeContext context) => Leaf('n$n');

  void bump() => setState(() => n++);
}

List<Branch> _directChildren(Branch branch) {
  final children = <Branch>[];
  branch.visitChildren(children.add);
  return children;
}

List<String> _tags(List<Branch> branches) =>
    branches.map((b) => (b.seed as Leaf).tag).toList();

void main() {
  late TreeOwner owner;
  setUp(() {
    owner = TreeOwner();
    _builds = 0;
  });
  tearDown(() => owner.dispose());

  group('mount', () {
    test(
      'mounts every declared child, in tree order, as a MultiChildBranch',
      () {
        final root = owner.mountRoot(
          const _Container([Leaf('a'), Leaf('b'), Leaf('c')]),
        );
        expect(root, isA<MultiChildBranch>());
        final mc = root as MultiChildBranch;
        expect(_tags(_directChildren(mc)), equals(['a', 'b', 'c']));
        expect(mc.children.every((Branch b) => b.mounted), isTrue);
      },
    );

    test('an empty container mounts with no children', () {
      final root = owner.mountRoot(const _Container([])) as MultiChildBranch;
      expect(root.children, isEmpty);
      expect(_directChildren(root), isEmpty);
    });
  });

  group('keyed reconcile', () {
    test('reordering keyed children preserves branch identity and order', () {
      final root =
          owner.mountRoot(
                const _Container([
                  Leaf('a', key: 'ka'),
                  Leaf('b', key: 'kb'),
                  Leaf('c', key: 'kc'),
                ]),
              )
              as MultiChildBranch;
      final a = root.children[0];
      final b = root.children[1];
      final c = root.children[2];

      root.update(
        const _Container([
          Leaf('c', key: 'kc'),
          Leaf('a', key: 'ka'),
          Leaf('b', key: 'kb'),
        ]),
      );

      // Same three branch instances, reordered — not rebuilt-from-scratch.
      expect(root.children, equals([c, a, b]));
      expect(identical(root.children[0], c), isTrue);
      expect(identical(root.children[1], a), isTrue);
      expect(identical(root.children[2], b), isTrue);
      expect(_tags(_directChildren(root)), equals(['c', 'a', 'b']));
    });

    test('a new keyed child mounts; a vanished keyed child unmounts', () {
      final root =
          owner.mountRoot(
                const _Container([Leaf('a', key: 'ka'), Leaf('b', key: 'kb')]),
              )
              as MultiChildBranch;
      final a = root.children[0];
      final b = root.children[1];

      root.update(
        const _Container([Leaf('a', key: 'ka'), Leaf('c', key: 'kc')]),
      );

      expect(identical(root.children[0], a), isTrue, reason: 'ka preserved');
      expect(b.mounted, isFalse, reason: 'kb dropped -> unmounted');
      expect(root.children.length, 2);
      expect((root.children[1].seed as Leaf).tag, 'c');
      expect(root.children[1].mounted, isTrue);
      expect(identical(root.children[1], b), isFalse, reason: 'kc is fresh');
    });

    test('a matched key whose runtimeType changed is replaced, not updated', () {
      final root =
          owner.mountRoot(const _Container([Leaf('a', key: 'k')]))
              as MultiChildBranch;
      final original = root.children.single;
      expect(original, isA<LeafBranch>());

      // Same key, different seed runtimeType (Leaf -> _Container) => canUpdate
      // is false => unmount + mount-fresh.
      root.update(const _Container([_Container([], key: 'k')]));

      expect(original.mounted, isFalse);
      expect(root.children.single, isA<MultiChildBranch>());
      expect(identical(root.children.single, original), isFalse);
    });

    test('two MultiChildSeed kinds are distinct reconcile tags at one key', () {
      // The seed's runtimeType is the reconcile tag, so a _Container and an
      // _OtherContainer never update into one another even at the same key —
      // the reason MultiChildSeed is abstract (one subclass per container kind).
      final root =
          owner.mountRoot(const _Container([_Container([], key: 'k')]))
              as MultiChildBranch;
      final original = root.children.single;
      expect(original, isA<MultiChildBranch>());

      root.update(const _Container([_OtherContainer([], key: 'k')]));

      expect(original.mounted, isFalse, reason: 'kind changed -> unmounted');
      expect(root.children.single, isA<MultiChildBranch>());
      expect(identical(root.children.single, original), isFalse);
    });
  });

  group('unkeyed (positional) reconcile', () {
    test(
      'unkeyed children match by position; growth mounts, shrink unmounts',
      () {
        final root =
            owner.mountRoot(const _Container([Leaf('a'), Leaf('b')]))
                as MultiChildBranch;
        final first = root.children[0];
        final second = root.children[1];

        // Grow to three: positions 0 and 1 are updated in place (same branches,
        // new tags), position 2 is fresh.
        root.update(const _Container([Leaf('x'), Leaf('y'), Leaf('z')]));
        expect(identical(root.children[0], first), isTrue);
        expect(identical(root.children[1], second), isTrue);
        expect(_tags(_directChildren(root)), equals(['x', 'y', 'z']));
        final third = root.children[2];

        // Shrink to one: the trailing unkeyed branches unmount.
        root.update(const _Container([Leaf('only')]));
        expect(identical(root.children.single, first), isTrue);
        expect(second.mounted, isFalse);
        expect(third.mounted, isFalse);
        expect(_tags(_directChildren(root)), equals(['only']));
      },
    );
  });

  group('identical-config fast path', () {
    test('reusing identical child seeds skips the child rebuild', () {
      const x = _Counting('x', key: 'kx');
      const y = _Counting('y', key: 'ky');
      final root =
          owner.mountRoot(const _Container([x, y])) as MultiChildBranch;
      expect(_builds, 2, reason: 'each child built once on mount');
      final bx = root.children[0];

      // New container instance, SAME child seed instances => updateChild takes
      // the identical-skip path: no child rebuild.
      root.update(const _Container([x, y]));
      expect(_builds, 2, reason: 'identical child seeds skipped');
      expect(identical(root.children[0], bx), isTrue);

      // Swap kx for a non-identical (but canUpdate-compatible) seed => that
      // child rebuilds; the untouched ky still skips.
      root.update(const _Container([_Counting('x2', key: 'kx'), y]));
      expect(_builds, 3, reason: 'only the changed child rebuilt');
      expect(
        identical(root.children[0], bx),
        isTrue,
        reason: 'kx updated in place',
      );
    });
  });

  group('lifecycle', () {
    test('unmounting the container unmounts every child', () {
      final root =
          owner.mountRoot(
                const _Container([Leaf('a', key: 'ka'), Leaf('b', key: 'kb')]),
              )
              as MultiChildBranch;
      final children = List<Branch>.of(root.children);

      owner.unmountRoot();

      expect(root.mounted, isFalse);
      expect(children.every((b) => !b.mounted), isTrue);
    });
  });

  group('nested topology (the_grid Grid -> Rig -> Step shape)', () {
    test('mounts the whole tree and a fresh walk reaches every branch', () {
      final root = owner.mountRoot(
        const _Container([
          _Container([Leaf('s1'), Leaf('s2')], key: 'rig-1'),
          _Container([Leaf('s3')], key: 'rig-2'),
        ]),
      );

      var count = 0;
      void walk(Branch b) {
        count++;
        b.visitChildren(walk);
      }

      walk(root);
      // root + 2 rigs + 3 steps = 6.
      expect(count, 6);
    });

    test(
      'a deep reorder preserves identity through intervening containers',
      () {
        final root =
            owner.mountRoot(
                  const _Container([
                    _Container([
                      Leaf('s1', key: 'ks1'),
                      Leaf('s2', key: 'ks2'),
                    ], key: 'rig-1'),
                  ]),
                )
                as MultiChildBranch;
        final rig = root.children.single as MultiChildBranch;
        final s1 = rig.children[0];
        final s2 = rig.children[1];

        root.update(
          const _Container([
            _Container([
              Leaf('s2', key: 'ks2'),
              Leaf('s1', key: 'ks1'),
            ], key: 'rig-1'),
          ]),
        );

        // The rig branch is preserved (key rig-1), and its inner steps are the
        // same instances, reordered — identity survives two reconcile levels.
        expect(identical(root.children.single, rig), isTrue);
        expect(identical(rig.children[0], s2), isTrue);
        expect(identical(rig.children[1], s1), isTrue);
      },
    );
  });

  group('composition with component branches', () {
    test(
      'a stateless component child composes transparently under the container',
      () {
        final root = owner.mountRoot(
          const _Container([Leaf('plain'), _Counting('built')]),
        );
        final direct = _directChildren(root);
        expect(direct.length, 2);
        // The second direct child is the component branch; recursion reaches its
        // built leaf.
        final componentChild = direct[1];
        expect(componentChild, isA<StatelessBranch>());
        expect(_tags(_directChildren(componentChild)), equals(['built']));
      },
    );

    test(
      'a stateful child rebuilds on setState while its siblings are untouched',
      () {
        final root =
            owner.mountRoot(
                  const _Container([Leaf('a', key: 'ka'), _Bump(key: 'kb')]),
                )
                as MultiChildBranch;
        final sibling = root.children[0];
        final bumpBranch = root.children[1];

        // Drive the stateful child's setState, then flush: only it is rebuilt.
        _capturedBump!.bump();
        final rebuilt = owner.flush();

        expect(rebuilt, contains(bumpBranch));
        expect(
          rebuilt,
          isNot(contains(sibling)),
          reason: 'an unrelated sibling is not rebuilt',
        );
        expect(identical(root.children[0], sibling), isTrue);
        expect(_tags(_directChildren(bumpBranch)), equals(['n1']));
      },
    );
  });

  group('duplicate-key guard', () {
    test('duplicate sibling keys trip the debug guard, naming the key', () {
      expect(
        () => owner.mountRoot(
          const _Container([Leaf('a', key: 'dup'), Leaf('b', key: 'dup')]),
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
  });
}
