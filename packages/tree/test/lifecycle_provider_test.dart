import 'dart:async';

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
  final List<TreeDependencyScope> dependencyScopes = [];
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
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) {
    events?.add('didChangeDependencies');
    watchingReader = reader;
    dependencyScopes.add(scope);
    if (watchInt) watched.add(reader.watch<int>());
    onDidChangeDependencies?.call();
  }

  @override
  void dispose() {
    disposeCount++;
    events?.add('dispose');
  }
}

final class _BuildProbe extends StatelessComponent {
  const _BuildProbe(this.participant, this.events);

  final _Participant participant;
  final List<String> events;

  @override
  Component build(BuildContext context) {
    expect(context.watch<_Participant>(), same(participant));
    events.add('build');
    return const _Leaf();
  }
}

final class _Leaf extends Component {
  const _Leaf();

  @override
  Element createElement() => _LeafElement(this);
}

final class _LeafElement extends Element {
  _LeafElement(_Leaf super.component);
}

final class _Slots extends MultiChildComponent {
  _Slots(List<Component> children) : super(children: children);
}

final class _InheritedHost extends StatefulComponent {
  const _InheritedHost({required this.onCreate, required this.describe});

  final void Function(_InheritedHostState state) onCreate;
  final Component Function() describe;

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
  Component build(BuildContext context) =>
      InheritedComponent<int>(value: _value, child: component.describe());
}

final class _ThrowingComponent extends StatelessComponent {
  const _ThrowingComponent();

  @override
  Component build(BuildContext context) => throw const _MountFailure();
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

Future<bool> _readScopeAfter(
  TreeDependencyScope scope,
  Future<void> release,
) async {
  await release;
  return scope.isCurrent;
}

void main() {
  test('created participant runs initState then didChangeDependencies before '
      'first build and watches every change', () {
    final events = <String>[];
    final participant = _Participant(events: events, watchInt: true);
    late _InheritedHostState host;
    var createCount = 0;
    final owner = BuildOwner();
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

  test(
    'each dependency pass receives a fresh scope and supersedes the prior pass',
    () {
      final participant = _Participant(watchInt: true);
      late _InheritedHostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _InheritedHost(
          onCreate: (state) => host = state,
          describe: () => LifecycleProvider<_Participant>.value(
            participant,
            child: const _Leaf(),
          ),
        ),
      );

      final first = participant.dependencyScopes.single;
      expect(first.isCurrent, isTrue);

      host.update(2);
      owner.flush();

      expect(participant.dependencyScopes, hasLength(2));
      final second = participant.dependencyScopes[1];
      expect(second, isNot(same(first)));
      expect(first.isCurrent, isFalse);
      expect(second.isCurrent, isTrue);

      host.update(3);
      owner.flush();

      expect(participant.dependencyScopes, hasLength(3));
      final third = participant.dependencyScopes[2];
      expect(third, isNot(same(second)));
      expect(first.isCurrent, isFalse);
      expect(second.isCurrent, isFalse);
      expect(third.isCurrent, isTrue);
    },
  );

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
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    final stringProvider =
        owner.mountRoot(
              InheritedComponent<String>(
                value: 'ambient',
                child: InheritedComponent<int>(
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
            as InheritedElement<String>;

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
    final createdOwner = BuildOwner();
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
    final adoptedOwner = BuildOwner();
    adoptedOwner.mountRoot(
      LifecycleProvider<_Participant>.value(adopted, child: const _Leaf()),
    );

    adoptedOwner.unmountRoot();
    adoptedOwner.unmountRoot();
    adoptedOwner.dispose();
    expect(adopted.disposeCount, 0);
  });

  test('unmount invalidates the outstanding scope without throwing', () async {
    Future<void> probe({required bool created}) async {
      final participant = _Participant();
      final owner = BuildOwner();
      final provider = created
          ? LifecycleProvider<_Participant>(
              create: () => participant,
              child: const _Leaf(),
            )
          : LifecycleProvider<_Participant>.value(
              participant,
              child: const _Leaf(),
            );
      owner.mountRoot(provider);

      final release = Completer<void>();
      final observation = _readScopeAfter(
        participant.dependencyScopes.single,
        release.future,
      );

      owner.unmountRoot();
      release.complete();

      expect(await observation, isFalse);
      expect(participant.disposeCount, created ? 1 : 0);
      owner.dispose();
    }

    await probe(created: true);
    await probe(created: false);
  });

  test('first-mount failure disposes a created participant once but not an '
      'adopted participant', () {
    final created = _Participant();
    final createdOwner = BuildOwner();
    addTearDown(createdOwner.dispose);

    expect(
      () => createdOwner.mountRoot(
        LifecycleProvider<_Participant>(
          create: () => created,
          child: const _ThrowingComponent(),
        ),
      ),
      throwsA(isA<_MountFailure>()),
    );
    expect(created.disposeCount, 1);
    expect(created.dependencyScopes.single.isCurrent, isFalse);

    final adopted = _Participant();
    final adoptedOwner = BuildOwner();
    addTearDown(adoptedOwner.dispose);

    expect(
      () => adoptedOwner.mountRoot(
        LifecycleProvider<_Participant>.value(
          adopted,
          child: const _ThrowingComponent(),
        ),
      ),
      throwsA(isA<_MountFailure>()),
    );
    expect(adopted.disposeCount, 0);
    expect(adopted.dependencyScopes.single.isCurrent, isFalse);
  });

  test(
    'old dependency scope becomes non-current while the provider remains mounted',
    () {
      final participant = _Participant(watchInt: true);
      late _InheritedHostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root =
          owner.mountRoot(
                _InheritedHost(
                  onCreate: (state) => host = state,
                  describe: () => LifecycleProvider<_Participant>.value(
                    participant,
                    child: const _Leaf(),
                  ),
                ),
              )
              as StatefulElement;
      final inherited = root.child as InheritedElement<int>;
      final lifecycleProviderElement = inherited.childElement!;
      final oldScope = participant.dependencyScopes.single;

      host.update(2);
      owner.flush();

      expect(inherited.childElement, same(lifecycleProviderElement));
      expect(lifecycleProviderElement.mounted, isTrue);
      expect(oldScope.isCurrent, isFalse);
      expect(participant.dependencyScopes.last.isCurrent, isTrue);
    },
  );

  group('same-key reconcile guard', () {
    const key = ValueKey<String>('participant');

    test('rejects create to value and keeps owned disposal armed', () {
      final original = _Participant();
      final replacement = _Participant();
      final owner = BuildOwner();
      final element = owner.mountRoot(
        LifecycleProvider<_Participant>(
          key: key,
          create: () => original,
          child: const _Leaf(),
        ),
      );

      expect(
        () => element.update(
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
      final owner = BuildOwner();
      final element = owner.mountRoot(
        LifecycleProvider<_Participant>.value(
          original,
          key: key,
          child: const _Leaf(),
        ),
      );

      expect(
        () => element.update(
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
      final owner = BuildOwner();
      final element = owner.mountRoot(
        LifecycleProvider<_Participant>.value(
          original,
          key: key,
          child: const _Leaf(),
        ),
      );

      expect(
        () => element.update(
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
