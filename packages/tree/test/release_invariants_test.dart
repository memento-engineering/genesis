// The three tree guards this file covers throw in RELEASE builds, not only
// under assertions. It is therefore run both ways in validation:
//   dart test test/release_invariants_test.dart   (assertions ON)
//   dart run  test/release_invariants_test.dart   (assertions OFF)
// Nothing here may expect an AssertionError.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

/// A stateful seed whose build calls setState — the pathological case that
/// drained forever in release.
class _SetStateDuringBuild extends StatefulSeed {
  const _SetStateDuringBuild();

  @override
  State<_SetStateDuringBuild> createState() => _SetStateDuringBuildState();
}

class _SetStateDuringBuildState extends State<_SetStateDuringBuild> {
  int _count = 0;

  @override
  Seed build(TreeContext context) {
    setState(() => _count++);
    return Leaf('count-$_count');
  }
}

/// A leaf that records its own unmount into [log] — the lifecycle probe that
/// proves the duplicate-key guard runs before any mutation.
class _Probe extends Seed {
  _Probe(this.tag, this.log, {super.key});

  final String tag;
  final List<String> log;

  @override
  _ProbeBranch createBranch() => _ProbeBranch(this);
}

class _ProbeBranch extends Branch {
  _ProbeBranch(_Probe super.seed);

  @override
  void unmount() {
    log.add((seed as _Probe).tag);
    super.unmount();
  }

  List<String> get log => (seed as _Probe).log;
}

void main() {
  test('setState during build throws StateError from flush and the drain '
      'terminates', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const _SetStateDuringBuild());

    expect(
      owner.flush,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('branch ${root.branchId}'),
            contains('setState during build'),
          ),
        ),
      ),
    );
    expect(owner.flush(), isEmpty);
  });

  test('duplicate sibling keys throw before any old branch is unmounted', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final log = <String>[];
    final root =
        owner.mountRoot(
              Node(
                'parent',
                children: [
                  _Probe('a', log, key: const ValueKey('k1')),
                  _Probe('b', log, key: const ValueKey('k2')),
                ],
              ),
            )
            as NodeBranch;
    final before = List<Branch>.of(root.children);

    expect(
      () => root.update(
        Node(
          'parent',
          children: [
            _Probe('a', log, key: const ValueKey('dup')),
            _Probe('b', log, key: const ValueKey('dup')),
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

    expect(log, isEmpty, reason: 'no old branch may be unmounted');
    expect(before.every((b) => b.mounted), isTrue);
    expect(root.children, orderedEquals(before));
  });

  test('Branch.update with an incompatible seed throws StateError', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const Leaf('a', key: ValueKey('a')));

    expect(
      () => root.update(const Leaf('a', key: ValueKey('b'))),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('canUpdate'),
        ),
      ),
    );
  });
}
