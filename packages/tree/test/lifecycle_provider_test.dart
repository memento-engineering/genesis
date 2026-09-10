import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

final class _Participant with TreeLifecycleParticipant {
  _Participant({
    this.events,
    this.watchInt = false,
    this.onInitState,
    this.onDidChangeDependencies,
  });

  final List<String>? events;
  final bool watchInt;
  final void Function()? onInitState;
  final void Function()? onDidChangeDependencies;

  TreeSnapshotReader? snapshotReader;
  TreeWatchingReader? watchingReader;
  int? snapshot;
  final List<int?> watched = [];
  int disposeCount = 0;

  @override
  void initState(TreeSnapshotReader reader) {
    events?.add('initState');
    snapshotReader = reader;
    snapshot = reader.read<int>();
    onInitState?.call();
  }

  @override
  void didChangeDependencies(TreeWatchingReader reader) {
    events?.add('didChangeDependencies');
    watchingReader = reader;
    if (watchInt) watched.add(reader.watch<int>());
    onDidChangeDependencies?.call();
  }

  @override
  void dispose() {
    disposeCount++;
    events?.add('dispose');
  }
}

final class _BuildProbe extends StatelessSeed {
  const _BuildProbe(this.participant, this.events);

  final _Participant participant;
  final List<String> events;

  @override
  Seed build(TreeContext context) {
    expect(context.watch<_Participant>(), same(participant));
    events.add('build');
    return const _Leaf();
  }
}

final class _Leaf extends Seed {
  const _Leaf();

  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(_Leaf super.seed);
}

final class _Slots extends MultiChildSeed {
  _Slots(List<Seed> children) : super(children: children);
}

final class _InheritedHost extends StatefulSeed {
  const _InheritedHost({required this.onCreate, required this.describe});

  final void Function(_InheritedHostState state) onCreate;
  final Seed Function() describe;

  @override
  State<_InheritedHost> createState() {
    final state = _InheritedHostState();
    onCreate(state);
    return state;
  }
}

final class _InheritedHostState extends State<_InheritedHost> {
  int _value = 1;

  void update(int value) => setState(() => _value = value);

  @override
  Seed build(TreeContext context) =>
      InheritedSeed<int>(value: _value, child: seed.describe());
}

final class _ThrowingSeed extends StatelessSeed {
  const _ThrowingSeed();

  @override
  Seed build(TreeContext context) => throw const _MountFailure();
}

final class _MountFailure implements Exception {
  const _MountFailure();
}

StateError _expectStateError(void Function() callback) {
  try {
    callback();
  } on StateError catch (error) {
    return error;
  }
  fail('Expected callback to throw StateError.');
}

void main() {
  test('created participant runs initState then didChangeDependencies before '
      'first build and watches every change', () {
    final events = <String>[];
    final participant = _Participant(events: events, watchInt: true);
    late _InheritedHostState host;
    var createCount = 0;
    final owner = TreeOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      _InheritedHost(
        onCreate: (state) => host = state,
        describe: () => LifecycleProvider<_Participant>(
          key: const ValueKey<String>('lifecycle'),
          create: () {
            createCount++;
            return participant;
          },
          child: _BuildProbe(participant, events),
        ),
      ),
    );

    expect(createCount, 1);
    expect(events, ['initState', 'didChangeDependencies', 'build']);
    expect(participant.snapshot, 1);
    expect(participant.watched, [1]);

    host.update(2);
    owner.flush();
    expect(events, [
      'initState',
      'didChangeDependencies',
      'build',
      'didChangeDependencies',
      'build',
    ]);
    expect(participant.watched, [1, 2]);
    expect(createCount, 1);

    host.update(3);
    owner.flush();
    expect(events, [
      'initState',
      'didChangeDependencies',
      'build',
      'didChangeDependencies',
      'build',
      'didChangeDependencies',
      'build',
    ]);
    expect(participant.watched, [1, 2, 3]);
    expect(createCount, 1);
  });

  test('captured readers throw StateError after their hook returns through the '
      'owner phase guard', () {
    final matchingPhaseErrors = <StateError>[];
    late _Participant first;
    final second = _Participant(
      onInitState: () {
        matchingPhaseErrors.add(
          _expectStateError(() => first.snapshotReader!.read<int>()),
        );
      },
      onDidChangeDependencies: () {
        matchingPhaseErrors.add(
          _expectStateError(() => first.watchingReader!.watch<String>()),
        );
      },
    );
    first = _Participant(watchInt: true);
    final owner = TreeOwner();
    addTearDown(owner.dispose);

    final stringProvider =
        owner.mountRoot(
              InheritedSeed<String>(
                value: 'ambient',
                child: InheritedSeed<int>(
                  value: 7,
                  child: _Slots([
                    LifecycleProvider<_Participant>.value(
                      first,
                      child: const _Leaf(),
                    ),
                    LifecycleProvider<_Participant>.value(
                      second,
                      child: const _Leaf(),
                    ),
                  ]),
                ),
              ),
            )
            as InheritedBranch<String>;

    expect(matchingPhaseErrors, hasLength(2));
    expect(
      matchingPhaseErrors[0].message,
      allOf(
        contains('TreeLifecyclePhase.initState'),
        contains('current phase is TreeLifecyclePhase.initState'),
        contains('revoked'),
      ),
    );
    expect(
      matchingPhaseErrors[1].message,
      allOf(
        contains('TreeLifecyclePhase.didChangeDependencies'),
        contains('current phase is TreeLifecyclePhase.didChangeDependencies'),
        contains('revoked'),
      ),
    );

    final snapshotError = _expectStateError(
      () => first.snapshotReader!.read<int>(),
    );
    expect(
      snapshotError.message,
      allOf(
        contains('TreeLifecyclePhase.initState'),
        contains('TreeLifecyclePhase.notInTreePhase'),
      ),
    );

    final watchingError = _expectStateError(
      () => first.watchingReader!.watch<String>(),
    );
    expect(
      watchingError.message,
      allOf(
        contains('TreeLifecyclePhase.didChangeDependencies'),
        contains('TreeLifecyclePhase.notInTreePhase'),
      ),
    );
    expect(
      stringProvider.dependents,
      isEmpty,
      reason: 'a revoked watching reader must not mutate dependency sets',
    );
  });

  test('created participant disposes once and adopted participant never '
      'disposes', () {
    final created = _Participant();
    final createdOwner = TreeOwner();
    createdOwner.mountRoot(
      LifecycleProvider<_Participant>(
        create: () => created,
        child: const _Leaf(),
      ),
    );

    createdOwner.unmountRoot();
    createdOwner.unmountRoot();
    createdOwner.dispose();
    expect(created.disposeCount, 1);

    final adopted = _Participant();
    final adoptedOwner = TreeOwner();
    adoptedOwner.mountRoot(
      LifecycleProvider<_Participant>.value(adopted, child: const _Leaf()),
    );

    adoptedOwner.unmountRoot();
    adoptedOwner.unmountRoot();
    adoptedOwner.dispose();
    expect(adopted.disposeCount, 0);
  });

  test('first-mount failure disposes a created participant once but not an '
      'adopted participant', () {
    final created = _Participant();
    final createdOwner = TreeOwner();
    addTearDown(createdOwner.dispose);

    expect(
      () => createdOwner.mountRoot(
        LifecycleProvider<_Participant>(
          create: () => created,
          child: const _ThrowingSeed(),
        ),
      ),
      throwsA(isA<_MountFailure>()),
    );
    expect(created.disposeCount, 1);

    final adopted = _Participant();
    final adoptedOwner = TreeOwner();
    addTearDown(adoptedOwner.dispose);

    expect(
      () => adoptedOwner.mountRoot(
        LifecycleProvider<_Participant>.value(
          adopted,
          child: const _ThrowingSeed(),
        ),
      ),
      throwsA(isA<_MountFailure>()),
    );
    expect(adopted.disposeCount, 0);
  });

  group('same-key reconcile guard', () {
    const key = ValueKey<String>('participant');

    test('rejects create to value and keeps owned disposal armed', () {
      final original = _Participant();
      final replacement = _Participant();
      final owner = TreeOwner();
      final branch = owner.mountRoot(
        LifecycleProvider<_Participant>(
          key: key,
          create: () => original,
          child: const _Leaf(),
        ),
      );

      expect(
        () => branch.update(
          LifecycleProvider<_Participant>.value(
            replacement,
            key: key,
            child: const _Leaf(),
          ),
        ),
        throwsStateError,
      );
      expect(original.disposeCount, 0);
      expect(replacement.disposeCount, 0);

      owner.dispose();
      expect(original.disposeCount, 1);
      expect(replacement.disposeCount, 0);
    });

    test('rejects value to create without constructing or disposing', () {
      final original = _Participant();
      final replacement = _Participant();
      var createCount = 0;
      final owner = TreeOwner();
      final branch = owner.mountRoot(
        LifecycleProvider<_Participant>.value(
          original,
          key: key,
          child: const _Leaf(),
        ),
      );

      expect(
        () => branch.update(
          LifecycleProvider<_Participant>(
            key: key,
            create: () {
              createCount++;
              return replacement;
            },
            child: const _Leaf(),
          ),
        ),
        throwsStateError,
      );
      expect(createCount, 0);

      owner.dispose();
      expect(original.disposeCount, 0);
      expect(replacement.disposeCount, 0);
    });

    test('rejects a non-identical adopted replacement', () {
      final original = _Participant();
      final replacement = _Participant();
      final owner = TreeOwner();
      final branch = owner.mountRoot(
        LifecycleProvider<_Participant>.value(
          original,
          key: key,
          child: const _Leaf(),
        ),
      );

      expect(
        () => branch.update(
          LifecycleProvider<_Participant>.value(
            replacement,
            key: key,
            child: const _Leaf(),
          ),
        ),
        throwsStateError,
      );

      owner.dispose();
      expect(original.disposeCount, 0);
      expect(replacement.disposeCount, 0);
    });
  });
}
