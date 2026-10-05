// Pins register entry `watch-nullability-follows-the-type-argument`:
//
// - D1: `watch<T>()` / `read<T>()` return `T` and throw a loud StateError that
//   names the type and the requester when no provider of `T` is in scope.
// - D2: `watch<T?>()` / `read<T?>()` return null for absence.
// - D3: the ProxyProvider family treats a non-nullable input as required (the
//   proxy is unavailable until it is present) and passes an absent nullable
//   input as null.
//
// Every declaration site is covered: the `ProviderBuildContext` extension on
// `BuildContext` (also through the `HookBuildContext` wrapper), and the
// lifecycle participant readers `TreeSnapshotReader.read` and
// `TreeWatchingReader.watch`.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

final class _Config {
  const _Config(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is _Config && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class _Absent {
  const _Absent();
}

final class _Derived {
  const _Derived(this.description);
  final String description;
}

final class _Leaf extends Component {
  const _Leaf();

  @override
  Element createElement() => _LeafElement(this);
}

final class _LeafElement extends Element {
  _LeafElement(_Leaf super.component);
}

/// Drains the microtask queue: availability notifications are delivered from
/// a microtask scheduled during the announcing flush.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// Runs [probe] on every build and records its outcome — the returned value,
/// or the thrown error — so a throwing lookup never fails the mount itself.
final class _Probe extends StatelessComponent {
  const _Probe(this.probe, this.outcomes, {super.key});

  final Object? Function(BuildContext context) probe;
  final List<Object?> outcomes;

  @override
  Component build(BuildContext context) {
    try {
      outcomes.add(probe(context));
    } on StateError catch (error) {
      outcomes.add(error);
    }
    return const _Leaf();
  }
}

/// The hook-context counterpart of [_Probe]: the lookup rides the
/// `HookBuildContext` wrapper instead of the canonical handle.
final class _HookProbe extends HookComponent {
  const _HookProbe(this.probe, this.outcomes);

  final Object? Function(BuildContext context) probe;
  final List<Object?> outcomes;

  @override
  Component build(HookBuildContext context) {
    try {
      outcomes.add(probe(context));
    } on StateError catch (error) {
      outcomes.add(error);
    }
    return const _Leaf();
  }
}

final class _Slots extends MultiChildComponent {
  _Slots(List<Component> children) : super(children: children);
}

final class _Host extends StatefulComponent {
  const _Host({required this.onCreate, required this.describe});

  final void Function(_HostState state) onCreate;
  final Component Function() describe;

  @override
  State<_Host> createState() {
    final state = _HostState();
    onCreate(state);
    return state;
  }
}

final class _HostState extends State<_Host> {
  Component Function()? _override;

  void swap(Component Function() describe) =>
      setState(() => _override = describe);

  @override
  Component build(BuildContext context) => (_override ?? component.describe)();
}

/// Mounts [child] under a ProviderScope, optionally under a `_Config`
/// provider, and returns the outcomes recorded by the first build.
List<Object?> _mount(
  Component Function(List<Object?> outcomes) child, {
  _Config? provided,
}) {
  final outcomes = <Object?>[];
  final owner = BuildOwner();
  addTearDown(owner.dispose);
  final probe = child(outcomes);
  owner.mountRoot(
    ProviderScope(
      child: provided == null
          ? probe
          : Provider<_Config>.value(provided, child: probe),
    ),
  );
  return outcomes;
}

TypeMatcher<StateError> _missNaming(String verb, String type) =>
    isA<StateError>().having(
      (error) => error.message,
      'message',
      allOf(
        contains('$verb<$type>()'),
        contains('no provider of $type'),
        contains('element '),
        contains('$verb<$type?>()'),
      ),
    );

final class _Participant with TreeLifecycleParticipant {
  _Participant({required this.onInit, required this.onDependencies});

  final Object? Function(TreeSnapshotReader reader) onInit;
  final Object? Function(TreeWatchingReader reader) onDependencies;
  final List<Object?> snapshots = [];
  final List<Object?> watched = [];

  @override
  void initState(TreeSnapshotReader reader) {
    try {
      snapshots.add(onInit(reader));
    } on StateError catch (error) {
      snapshots.add(error);
    }
  }

  @override
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) {
    try {
      watched.add(onDependencies(reader));
    } on StateError catch (error) {
      watched.add(error);
    }
  }
}

_Participant _mountParticipant({
  required Object? Function(TreeSnapshotReader reader) onInit,
  required Object? Function(TreeWatchingReader reader) onDependencies,
  _Config? provided,
}) {
  final participant = _Participant(
    onInit: onInit,
    onDependencies: onDependencies,
  );
  final owner = BuildOwner();
  addTearDown(owner.dispose);
  final lifecycle = LifecycleProvider<_Participant>.value(
    participant,
    child: const _Leaf(),
  );
  owner.mountRoot(
    ProviderScope(
      child: provided == null
          ? lifecycle
          : Provider<_Config>.value(provided, child: lifecycle),
    ),
  );
  return participant;
}

void main() {
  group('BuildContext.watch (D1/D2)', () {
    test('present + non-nullable returns the value', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.watch<_Config>().name, o),
        provided: const _Config('a'),
      );
      expect(outcomes, ['a']);
    });

    test('present + nullable returns the value', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.watch<_Config?>()?.name, o),
        provided: const _Config('a'),
      );
      expect(outcomes, ['a']);
    });

    test('absent + non-nullable throws a StateError naming the type and the '
        'requesting element', () {
      final outcomes = _mount(
        (o) => _Probe(
          (context) => context.watch<_Absent>(),
          o,
          key: const ValueKey<String>('requester'),
        ),
      );
      expect(outcomes, [_missNaming('watch', '_Absent')]);
      expect(
        (outcomes.single! as StateError).message,
        contains('requester'),
        reason: 'the requesting element is named by id and key',
      );
    });

    test('absent + nullable returns null', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.watch<_Absent?>(), o),
      );
      expect(outcomes, [null]);
    });

    test('through the HookBuildContext wrapper: both arms', () {
      final present = _mount(
        (o) => _HookProbe((context) => context.watch<_Config>().name, o),
        provided: const _Config('hooked'),
      );
      expect(present, ['hooked']);
      final nullable = _mount(
        (o) => _HookProbe((context) => context.watch<_Absent?>(), o),
      );
      expect(nullable, [null]);
      final required = _mount(
        (o) => _HookProbe((context) => context.watch<_Absent>(), o),
      );
      expect(required, [_missNaming('watch', '_Absent')]);
    });

    test('a non-nullable hit registers the dependency: a value change '
        'rebuilds the watcher', () {
      final outcomes = <Object?>[];
      late _HostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final probe = _Probe(
        (context) => context.watch<_Config>().name,
        outcomes,
      );
      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () =>
                Provider<_Config>.value(const _Config('a'), child: probe),
          ),
        ),
      );
      expect(outcomes, ['a']);

      host.swap(
        () => Provider<_Config>.value(const _Config('b'), child: probe),
      );
      owner.flush();
      expect(outcomes, ['a', 'b']);
    });

    test('a non-nullable miss still parks its registration: the provider '
        'appearing later wakes the watcher, which then resolves', () async {
      final outcomes = <Object?>[];
      late _HostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final probe = _Probe(
        (context) => context.watch<_Config>().name,
        outcomes,
      );
      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => probe,
          ),
        ),
      );
      expect(outcomes, [_missNaming('watch', '_Config')]);

      host.swap(
        () => Provider<_Config>.value(const _Config('late'), child: probe),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(outcomes.last, 'late');
    });
  });

  group('BuildContext.read (D1/D2)', () {
    test('present + non-nullable returns the value', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.read<_Config>().name, o),
        provided: const _Config('a'),
      );
      expect(outcomes, ['a']);
    });

    test('present + nullable returns the value', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.read<_Config?>()?.name, o),
        provided: const _Config('a'),
      );
      expect(outcomes, ['a']);
    });

    test('absent + non-nullable throws a StateError naming the type', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.read<_Absent>(), o),
      );
      expect(outcomes, [_missNaming('read', '_Absent')]);
    });

    test('absent + nullable returns null', () {
      final outcomes = _mount(
        (o) => _Probe((context) => context.read<_Absent?>(), o),
      );
      expect(outcomes, [null]);
    });

    test('read never registers: a nullable miss parks nothing', () {
      late AvailabilityRegistry registry;
      _mount(
        (o) => _Probe((context) {
          registry = context.read<AvailabilityRegistry>();
          return context.read<_Absent?>();
        }, o),
      );
      expect(registry.debugPendingOf<_Absent>(), isEmpty);
    });
  });

  group('lifecycle readers (D1/D2)', () {
    test('TreeSnapshotReader.read: present, both type arguments', () {
      final participant = _mountParticipant(
        onInit: (reader) => [
          reader.read<_Config>().name,
          reader.read<_Config?>()?.name,
        ],
        onDependencies: (reader) => null,
        provided: const _Config('a'),
      );
      expect(participant.snapshots, [
        ['a', 'a'],
      ]);
    });

    test('TreeSnapshotReader.read: absent + non-nullable throws naming the '
        'type and the requesting element', () {
      final participant = _mountParticipant(
        onInit: (reader) => reader.read<_Absent>(),
        onDependencies: (reader) => null,
      );
      expect(participant.snapshots, [_missNaming('read', '_Absent')]);
    });

    test('TreeSnapshotReader.read: absent + nullable returns null', () {
      final participant = _mountParticipant(
        onInit: (reader) => reader.read<_Absent?>(),
        onDependencies: (reader) => null,
      );
      expect(participant.snapshots, [null]);
    });

    test('TreeWatchingReader.watch: present, both type arguments', () {
      final participant = _mountParticipant(
        onInit: (reader) => null,
        onDependencies: (reader) => [
          reader.watch<_Config>().name,
          reader.watch<_Config?>()?.name,
        ],
        provided: const _Config('a'),
      );
      expect(participant.watched, [
        ['a', 'a'],
      ]);
    });

    test('TreeWatchingReader.watch: absent + non-nullable throws naming the '
        'type and the requesting element', () {
      final participant = _mountParticipant(
        onInit: (reader) => null,
        onDependencies: (reader) => reader.watch<_Absent>(),
      );
      expect(participant.watched, [_missNaming('watch', '_Absent')]);
    });

    test('TreeWatchingReader.watch: absent + nullable returns null', () {
      final participant = _mountParticipant(
        onInit: (reader) => null,
        onDependencies: (reader) => reader.watch<_Absent?>(),
      );
      expect(participant.watched, [null]);
    });
  });

  group('ProxyProvider family (D3)', () {
    test('a non-nullable input makes the proxy unavailable until present, '
        'then the proxy builds', () async {
      final outcomes = <Object?>[];
      final updates = <String>[];
      late _HostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      Component proxy() => ProxyProvider<_Config, _Derived>(
        update: (context, config, previous) {
          updates.add(config.name);
          return _Derived('from ${config.name}');
        },
        child: _Probe(
          (context) => context.watch<_Derived?>()?.description,
          outcomes,
        ),
      );
      owner.mountRoot(
        ProviderScope(
          child: _Host(onCreate: (state) => host = state, describe: proxy),
        ),
      );
      expect(updates, isEmpty, reason: 'a required input is absent');
      expect(outcomes, [null], reason: 'no _Derived is projected');

      host.swap(
        () => Provider<_Config>.value(const _Config('a'), child: proxy()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(updates, ['a']);
      expect(outcomes.last, 'from a');
    });

    test('a nullable input is passed as null while absent, and the proxy '
        'builds', () {
      final updates = <String?>[];
      final outcomes = _mount(
        (o) => ProxyProvider<_Absent?, _Derived>(
          update: (context, absent, previous) {
            updates.add(absent?.toString());
            return _Derived('absent is ${absent == null ? 'null' : 'set'}');
          },
          child: _Probe((context) => context.watch<_Derived>().description, o),
        ),
      );
      expect(updates, [null]);
      expect(outcomes, ['absent is null']);
    });

    test('mixed arity: a nullable input does not gate, a non-nullable one '
        'does', () async {
      final outcomes = <Object?>[];
      final updates = <String>[];
      late _HostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      Component proxy() => ProxyProvider2<_Absent?, _Config, _Derived>(
        update: (context, absent, config, previous) {
          updates.add('${absent == null ? 'null' : 'set'}/${config.name}');
          return _Derived(config.name);
        },
        child: _Probe(
          (context) => context.watch<_Derived?>()?.description,
          outcomes,
        ),
      );
      owner.mountRoot(
        ProviderScope(
          child: _Host(onCreate: (state) => host = state, describe: proxy),
        ),
      );
      expect(updates, isEmpty, reason: 'the non-nullable _Config is absent');
      expect(outcomes, [null]);

      host.swap(
        () => Provider<_Config>.value(const _Config('c'), child: proxy()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(updates, ['null/c']);
      expect(outcomes.last, 'c');
    });

    test('a nullable input that appears later is delivered on the next '
        'derive', () async {
      final updates = <String?>[];
      late _HostState host;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      Component proxy() => ProxyProvider<_Config?, _Derived>(
        update: (context, config, previous) {
          updates.add(config?.name);
          return _Derived(config?.name ?? 'none');
        },
        child: const _Leaf(),
      );
      owner.mountRoot(
        ProviderScope(
          child: _Host(onCreate: (state) => host = state, describe: proxy),
        ),
      );
      expect(updates, [null]);

      host.swap(
        () => Provider<_Config>.value(const _Config('now'), child: proxy()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(updates.last, 'now');
    });
  });

  group('AvailabilityRegistry (existing behaviour)', () {
    test('a parked registration wakes the dependent when the provider '
        'appears later', () async {
      final outcomes = <Object?>[];
      late _HostState host;
      late AvailabilityRegistry registry;
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final probe = _Probe((context) {
        registry = context.read<AvailabilityRegistry>();
        return context.watch<_Config?>()?.name;
      }, outcomes);
      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => probe,
          ),
        ),
      );
      expect(outcomes, [null]);
      expect(registry.debugPendingOf<_Config>(), hasLength(1));

      host.swap(
        () => Provider<_Config>.value(const _Config('appeared'), child: probe),
      );
      owner.flush();
      expect(
        registry.debugPendingOf<_Config>(),
        isEmpty,
        reason: 'the provider mount drained the nullable watcher\'s bucket',
      );
      await _pump();
      owner.flush();
      expect(outcomes.last, 'appeared');
    });

    test('required and nullable watchers of one type share one bucket', () {
      late AvailabilityRegistry registry;
      final outcomes = <Object?>[];
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _Probe((context) {
              registry = context.read<AvailabilityRegistry>();
              return context.watch<_Absent>();
            }, outcomes),
            _Probe((context) => context.watch<_Absent?>(), outcomes),
          ]),
        ),
      );
      expect(registry.debugPendingOf<_Absent>(), hasLength(2));
      expect(
        registry.debugPendingOf<_Absent?>(),
        registry.debugPendingOf<_Absent>(),
      );
    });
  });

  group('one key per provided type', () {
    test('a Provider<int> is found by watch<int>() and watch<int?>(); '
        'watch<String>() under it throws naming String and the element', () {
      final outcomes = _mount(
        (o) => Provider<int>.value(
          7,
          child: _Probe(
            (context) => [
              context.watch<int>(),
              context.watch<int?>(),
              context.read<int>(),
              context.read<int?>(),
            ],
            o,
          ),
        ),
      );
      expect(outcomes, [
        [7, 7, 7, 7],
      ]);
      final missing = _mount(
        (o) => Provider<int>.value(
          7,
          child: _Probe((context) => context.watch<String>(), o),
        ),
      );
      expect(missing, [_missNaming('watch', 'String')]);
    });

    test('the base lookup pair stays an exact match: a provider registers '
        'under the nullable spelling, a plain InheritedComponent under its '
        'own', () {
      final outcomes = <Object?>[];
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        InheritedComponent<_Absent>(
          value: const _Absent(),
          child: Provider<_Config>.value(
            const _Config('provided'),
            child: _Probe(
              (context) => [
                context.getInheritedValueOfExactType<_Config?>()?.name,
                context.getInheritedValueOfExactType<_Config>(),
                context.getInheritedValueOfExactType<_Absent>() != null,
                context.getInheritedValueOfExactType<_Absent?>(),
              ],
              outcomes,
            ),
          ),
        ),
      );
      expect(outcomes, [
        ['provided', null, true, null],
      ]);
    });
  });
}
