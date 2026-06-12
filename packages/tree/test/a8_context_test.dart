// A8 (ADR-0001 Decision 2): Branch does NOT implement TreeContext — the
// context is a separate, invalidatable capability handle. These tests make
// the fork executable: no concrete branch kind is a TreeContext, and a handle
// captured in build() and held across an async gap throws StateError once its
// branch unmounts.
import 'dart:async';

import 'package:test/test.dart';
import 'package:tree/tree.dart';

import 'src/fixtures.dart';

class _StatelessProbe extends StatelessSeed {
  const _StatelessProbe();
  @override
  Seed build(TreeContext context) => const Leaf('stateless-child');
}

class _StatefulProbe extends StatefulSeed {
  const _StatefulProbe();
  @override
  _StatefulProbeState createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  @override
  Seed build(TreeContext context) => const Leaf('stateful-child');
}

class _CaptureSeed extends StatelessSeed {
  _CaptureSeed(this.onBuild);
  final void Function(TreeContext context) onBuild;
  @override
  Seed build(TreeContext context) {
    onBuild(context);
    return const Leaf('captured');
  }
}

void main() {
  group('A8: no Branch implements TreeContext', () {
    test('every concrete Branch kind in a full tree fails `is TreeContext`', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        Node(
          'root',
          children: [
            const Leaf('bare'),
            const _StatelessProbe(),
            const _StatefulProbe(),
            InheritedSeed<String>(value: 'v', child: const _StatelessProbe()),
          ],
        ),
      );

      final all = <Branch>[];
      void collect(Branch branch) {
        all.add(branch);
        branch.visitChildren(collect);
      }

      collect(root);

      // Prove the walk covered every concrete kind: container, bare leaf,
      // stateless, stateful, inherited.
      final kinds = all.map((b) => b.runtimeType.toString()).toSet();
      expect(
        kinds,
        containsAll(<String>[
          'NodeBranch',
          'LeafBranch',
          'StatelessBranch',
          'StatefulBranch',
        ]),
      );
      expect(kinds.any((k) => k.startsWith('InheritedBranch')), isTrue);

      for (final branch in all) {
        expect(
          branch is TreeContext,
          isFalse,
          reason:
              '${branch.runtimeType} must not implement TreeContext (A8: '
              'the Element≡BuildContext original sin is shed by construction)',
        );
      }
    });

    test('the handle passed to build() is not a Branch', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      TreeContext? captured;
      owner.mountRoot(_CaptureSeed((context) => captured = context));
      expect(captured, isNotNull);
      expect(captured, isNot(isA<Branch>()));
    });
  });

  group('A8: handle validity', () {
    test('handle is live while mounted: delegates and drives rebuilds', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      var builds = 0;
      TreeContext? captured;
      final root = owner.mountRoot(
        _CaptureSeed((context) {
          builds++;
          captured = context;
        }),
      );

      expect(builds, 1);
      expect(captured!.mounted, isTrue);
      expect(captured!.branchId, equals(root.branchId));
      expect(captured!.key, equals(root.key));

      captured!.markNeedsRebuild();
      final rebuilt = owner.flush();
      expect(builds, 2);
      expect(rebuilt, equals([root]));
    });

    test('handle captured in build() throws StateError after its branch '
        'unmounts (the async-gap case)', () async {
      final owner = TreeOwner();
      TreeContext? captured;
      owner.mountRoot(_CaptureSeed((context) => captured = context));
      final handle = captured!;
      expect(handle.mounted, isTrue);

      // The async gap: an agent reads the projection, deliberates, then
      // acts — and the tree moves under it in between.
      await Future<void>.delayed(Duration.zero);
      owner.unmountRoot();

      // `mounted` stays queryable — the safe staleness probe...
      expect(handle.mounted, isFalse);
      // ...every other capability throws.
      expect(() => handle.branchId, throwsStateError);
      expect(() => handle.key, throwsStateError);
      expect(() => handle.markNeedsRebuild(), throwsStateError);
      expect(
        () => handle.dependOnInheritedSeedOfExactType<String>(),
        throwsStateError,
      );
    });

    test('State.context is the handle, and dies with the branch', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(const _StatefulProbe()) as StatefulBranch;
      final context = root.state.context;
      expect(context, isNot(same(root)));
      expect(context.mounted, isTrue);

      owner.unmountRoot();

      expect(context.mounted, isFalse);
      expect(() => context.markNeedsRebuild(), throwsStateError);
    });
  });
}
