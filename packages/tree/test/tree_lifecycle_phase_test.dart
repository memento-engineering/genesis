// ignore_for_file: invalid_use_of_protected_member

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

class _PhaseRecordingComponent extends Component {
  const _PhaseRecordingComponent();

  @override
  _PhaseRecordingElement createElement() => _PhaseRecordingElement(this);
}

class _PhaseRecordingElement extends Element {
  _PhaseRecordingElement(super.component);

  final List<TreeLifecyclePhase> phases = [];

  @override
  void performRebuild() {
    phases.add(owner!.lifecyclePhaseGuard.phase);
  }
}

class _LifecycleRecord {
  final Map<String, TreeLifecyclePhase> phases = {};
}

class _LifecycleProbeComponent extends StatefulComponent {
  const _LifecycleProbeComponent({required this.owner, required this.record});

  final BuildOwner owner;
  final _LifecycleRecord record;

  @override
  State<_LifecycleProbeComponent> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbeComponent> {
  TreeLifecyclePhase get _phase => component.owner.lifecyclePhaseGuard.phase;

  @override
  void initState() {
    component.record.phases['initState'] = _phase;
  }

  @override
  void didChangeDependencies() {
    component.record.phases['didChangeDependencies'] = _phase;
  }

  @override
  Component build(BuildContext context) {
    component.record.phases['build'] = _phase;
    context.dependOnInheritedValueOfExactType<int>();
    return const _PhaseRecordingComponent();
  }

  @override
  void dispose() {
    component.record.phases['dispose'] = _phase;
  }
}

class _InitMessageComponent extends StatefulComponent {
  const _InitMessageComponent();

  @override
  State<_InitMessageComponent> createState() => _InitMessageState();
}

class _InitMessageState extends State<_InitMessageComponent> {
  @override
  void initState() {
    context.dependOnInheritedValueOfExactType<int>();
  }

  @override
  Component build(BuildContext context) => const _PhaseRecordingComponent();
}

class _DisposeMessageComponent extends StatefulComponent {
  const _DisposeMessageComponent();

  @override
  State<_DisposeMessageComponent> createState() => _DisposeMessageState();
}

class _DisposeMessageState extends State<_DisposeMessageComponent> {
  bool _registerDependency = true;

  @override
  Component build(BuildContext context) => const _PhaseRecordingComponent();

  @override
  void dispose() {
    if (_registerDependency) {
      _registerDependency = false;
      context.dependOnInheritedValueOfExactType<int>();
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

  test('BuildOwner composes the existing flush marker as building', () {
    final owner = BuildOwner();
    addTearDown(owner.dispose);
    final element =
        owner.mountRoot(const _PhaseRecordingComponent())
            as _PhaseRecordingElement;

    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
    element.markNeedsRebuild();

    expect(owner.flush(), [element]);
    expect(element.phases, [TreeLifecyclePhase.building]);
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
  });

  test('StatefulElement drives each callback through the owner guard', () {
    final owner = BuildOwner();
    final record = _LifecycleRecord();
    final provider =
        owner.mountRoot(
              InheritedComponent<int>(
                value: 7,
                child: _LifecycleProbeComponent(owner: owner, record: record),
              ),
            )
            as InheritedElement<int>;
    final element = provider.childElement as StatefulElement;

    expect(record.phases, {
      'initState': TreeLifecyclePhase.initState,
      'didChangeDependencies': TreeLifecyclePhase.didChangeDependencies,
      'build': TreeLifecyclePhase.building,
    });
    expect(provider.dependents, {element});
    expect(element.dependencies, {provider});
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);

    owner.unmountRoot();

    expect(record.phases['dispose'], TreeLifecyclePhase.dispose);
    expect(owner.lifecyclePhaseGuard.phase, TreeLifecyclePhase.notInTreePhase);
  });

  test('existing dependency assert messages remain byte-identical', () {
    const initStateMessage =
        'dependOnInheritedValueOfExactType<int>() called from initState. '
        'initState never re-runs, so caching the value read here goes stale '
        'when the provider changes. For a one-shot read use '
        'getInheritedValueOfExactType<int>(); to cache and track the value, move '
        'the lookup to didChangeDependencies(), which re-runs on every change.';
    const disposeMessage =
        'dependOnInheritedValueOfExactType<int>() called from dispose. The '
        'element is unmounting — a dependency registered now can never observe '
        'a change. Use getInheritedValueOfExactType<int>() for a last read '
        'during teardown.';

    final initOwner = BuildOwner();
    final initElement = const _InitMessageComponent().createElement()
      ..owner = initOwner;
    expect(
      () => initElement.mount(null, null),
      throwsA(
        isA<AssertionError>().having(
          (error) => error.message,
          'message',
          initStateMessage,
        ),
      ),
    );
    initElement.unmount();
    initOwner.dispose();

    final disposeOwner = BuildOwner();
    disposeOwner.mountRoot(const _DisposeMessageComponent());
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
