// ignore_for_file: invalid_use_of_protected_member

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

class _PhaseRecordingSeed extends Seed {
  const _PhaseRecordingSeed();

  @override
  _PhaseRecordingBranch createBranch() => _PhaseRecordingBranch(this);
}

class _PhaseRecordingBranch extends Branch {
  _PhaseRecordingBranch(super.seed);

  final List<TreeLifecyclePhase> phases = [];

  @override
  void performRebuild() {
    phases.add(owner!.lifecyclePhaseGuard.phase);
  }
}

class _LifecycleRecord {
  final Map<String, TreeLifecyclePhase> phases = {};
}

class _LifecycleProbeSeed extends StatefulSeed {
  const _LifecycleProbeSeed({required this.owner, required this.record});

  final TreeOwner owner;
  final _LifecycleRecord record;

  @override
  State<_LifecycleProbeSeed> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbeSeed> {
  TreeLifecyclePhase get _phase => seed.owner.lifecyclePhaseGuard.phase;

  @override
  void initState() {
    seed.record.phases['initState'] = _phase;
  }

  @override
  void didChangeDependencies() {
    seed.record.phases['didChangeDependencies'] = _phase;
  }

  @override
  Seed build(TreeContext context) {
    seed.record.phases['build'] = _phase;
    context.dependOnInheritedSeedOfExactType<int>();
    return const _PhaseRecordingSeed();
  }

  @override
  void dispose() {
    seed.record.phases['dispose'] = _phase;
  }
}

class _InitMessageSeed extends StatefulSeed {
  const _InitMessageSeed();

  @override
  State<_InitMessageSeed> createState() => _InitMessageState();
}

class _InitMessageState extends State<_InitMessageSeed> {
  @override
  void initState() {
    context.dependOnInheritedSeedOfExactType<int>();
  }

  @override
  Seed build(TreeContext context) => const _PhaseRecordingSeed();
}

class _DisposeMessageSeed extends StatefulSeed {
  const _DisposeMessageSeed();

  @override
  State<_DisposeMessageSeed> createState() => _DisposeMessageState();
}

class _DisposeMessageState extends State<_DisposeMessageSeed> {
  bool _registerDependency = true;

  @override
  Seed build(TreeContext context) => const _PhaseRecordingSeed();

  @override
  void dispose() {
    if (_registerDependency) {
      _registerDependency = false;
      context.dependOnInheritedSeedOfExactType<int>();
    }
  }
}

void main() {
  test(
    'TreeLifecyclePhaseGuard exposes all phases and restores nested scopes',
    () {
      var ownerIsBuilding = false;
      final guard = TreeLifecyclePhaseGuard(isBuilding: () => ownerIsBuilding);

      expect(TreeLifecyclePhase.values, [
        TreeLifecyclePhase.notInTreePhase,
        TreeLifecyclePhase.initState,
        TreeLifecyclePhase.didChangeDependencies,
        TreeLifecyclePhase.building,
        TreeLifecyclePhase.dispose,
      ]);
      expect(guard.phase, TreeLifecyclePhase.notInTreePhase);

      for (final explicitPhase in TreeLifecyclePhase.values) {
        guard.runInPhase<void>(explicitPhase, () {
          expect(guard.phase, explicitPhase);
        });
        expect(guard.phase, TreeLifecyclePhase.notInTreePhase);
      }

      ownerIsBuilding = true;
      expect(guard.phase, TreeLifecyclePhase.building);
      guard.runInPhase<void>(TreeLifecyclePhase.initState, () {
        expect(guard.phase, TreeLifecyclePhase.initState);
        guard.runInPhase<void>(TreeLifecyclePhase.didChangeDependencies, () {
          expect(guard.phase, TreeLifecyclePhase.didChangeDependencies);
        });
        expect(guard.phase, TreeLifecyclePhase.initState);
      });
      expect(guard.phase, TreeLifecyclePhase.building);

      expect(
        () => guard.runInPhase<void>(
          TreeLifecyclePhase.dispose,
          () => throw StateError('probe'),
        ),
        throwsStateError,
      );
      expect(guard.phase, TreeLifecyclePhase.building);

      ownerIsBuilding = false;
      expect(guard.phase, TreeLifecyclePhase.notInTreePhase);
    },
  );

  test('TreeOwner composes the existing flush marker as building', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final branch =
        owner.mountRoot(const _PhaseRecordingSeed()) as _PhaseRecordingBranch;

    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
    branch.markNeedsRebuild();

    expect(owner.flush(), [branch]);
    expect(branch.phases, [TreeLifecyclePhase.building]);
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
  });

  test('StatefulBranch drives each callback through the owner guard', () {
    final owner = TreeOwner();
    final record = _LifecycleRecord();
    final provider =
        owner.mountRoot(
              InheritedSeed<int>(
                value: 7,
                child: _LifecycleProbeSeed(owner: owner, record: record),
              ),
            )
            as InheritedBranch<int>;
    final branch = provider.childBranch as StatefulBranch;

    expect(record.phases, {
      'initState': TreeLifecyclePhase.initState,
      'didChangeDependencies': TreeLifecyclePhase.didChangeDependencies,
      'build': TreeLifecyclePhase.building,
    });
    expect(provider.dependents, {branch});
    expect(branch.dependencies, {provider});
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);

    owner.unmountRoot();

    expect(record.phases['dispose'], TreeLifecyclePhase.dispose);
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
  });

  test('existing dependency assert messages remain byte-identical', () {
    const initStateMessage =
        'dependOnInheritedSeedOfExactType<int>() called from initState. '
        'initState never re-runs, so caching the value read here goes stale '
        'when the provider changes. For a one-shot read use '
        'getInheritedSeedOfExactType<int>(); to cache and track the value, move '
        'the lookup to didChangeDependencies(), which re-runs on every change.';
    const disposeMessage =
        'dependOnInheritedSeedOfExactType<int>() called from dispose. The '
        'branch is unmounting — a dependency registered now can never observe '
        'a change. Use getInheritedSeedOfExactType<int>() for a last read '
        'during teardown.';

    final initOwner = TreeOwner();
    final initBranch = const _InitMessageSeed().createBranch()
      ..owner = initOwner;
    expect(
      () => initBranch.mount(null, null),
      throwsA(
        isA<AssertionError>().having(
          (error) => error.message,
          'message',
          initStateMessage,
        ),
      ),
    );
    initBranch.unmount();
    initOwner.dispose();

    final disposeOwner = TreeOwner();
    disposeOwner.mountRoot(const _DisposeMessageSeed());
    expect(
      disposeOwner.unmountRoot,
      throwsA(
        isA<AssertionError>().having(
          (error) => error.message,
          'message',
          disposeMessage,
        ),
      ),
    );
    expect(
      disposeOwner.lifecyclePhaseGuard.phase,
      TreeLifecyclePhase.notInTreePhase,
    );
    disposeOwner.unmountRoot();
  });
}
