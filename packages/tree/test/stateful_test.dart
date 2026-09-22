// ignore_for_file: invalid_use_of_protected_member
// Port of perception's stateful_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

// --- fixtures ---

class _Leaf extends Component {
  const _Leaf();
  @override
  _LeafElement createElement() => _LeafElement(this);
}

class _LeafElement extends Element {
  _LeafElement(super.component);
}

class _TrackedComponent extends StatefulComponent {
  const _TrackedComponent();
  @override
  _TrackedState createState() => _TrackedState();
}

class _TrackedState extends State<_TrackedComponent> {
  final calls = <String>[];
  int count = 0;

  @override
  void initState() => calls.add('initState');

  @override
  void didChangeDependencies() => calls.add('dcd');

  @override
  Component build(BuildContext context) {
    calls.add('build');
    return const _Leaf();
  }

  @override
  void dispose() => calls.add('dispose');
}

class _ReaderComponent extends StatefulComponent {
  const _ReaderComponent();
  @override
  _ReaderState createState() => _ReaderState();
}

class _ReaderState extends State<_ReaderComponent> {
  final calls = <String>[];
  int? lastValue;

  @override
  void didChangeDependencies() {
    calls.add('dcd');
    lastValue = context.dependOnInheritedValueOfExactType<int>();
  }

  @override
  Component build(BuildContext context) {
    calls.add('build');
    return const _Leaf();
  }
}

class _InitGetComponent extends StatefulComponent {
  const _InitGetComponent();
  @override
  _InitGetState createState() => _InitGetState();
}

class _InitGetState extends State<_InitGetComponent> {
  int? initValue;

  @override
  void initState() {
    initValue = context.getInheritedValueOfExactType<int>();
  }

  @override
  Component build(BuildContext context) => const _Leaf();
}

class _InitDependComponent extends StatefulComponent {
  const _InitDependComponent();
  @override
  _InitDependState createState() => _InitDependState();
}

class _InitDependState extends State<_InitDependComponent> {
  @override
  void initState() {
    context.dependOnInheritedValueOfExactType<int>();
  }

  @override
  Component build(BuildContext context) => const _Leaf();
}

class _DisposeDependComponent extends StatefulComponent {
  const _DisposeDependComponent();
  @override
  _DisposeDependState createState() => _DisposeDependState();
}

class _DisposeDependState extends State<_DisposeDependComponent> {
  @override
  Component build(BuildContext context) => const _Leaf();

  @override
  void dispose() {
    context.dependOnInheritedValueOfExactType<int>();
  }
}

class _DisposeGetComponent extends StatefulComponent {
  const _DisposeGetComponent();
  @override
  _DisposeGetState createState() => _DisposeGetState();
}

class _DisposeGetState extends State<_DisposeGetComponent> {
  int? disposeValue;

  @override
  Component build(BuildContext context) => const _Leaf();

  @override
  void dispose() {
    disposeValue = context.getInheritedValueOfExactType<int>();
  }
}

// --- tests ---

void main() {
  group('StatefulComponent', () {
    test('createElement returns StatefulElement', () {
      expect(const _TrackedComponent().createElement(), isA<StatefulElement>());
    });
  });

  group('StatefulElement lifecycle on mount', () {
    test('order: initState → didChangeDependencies → build', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(const _TrackedComponent()) as StatefulElement;
      expect(
        (element.state as _TrackedState).calls,
        equals(['initState', 'dcd', 'build']),
      );
    });

    test('state.component is the StatefulComponent config', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(const _TrackedComponent()) as StatefulElement;
      expect(element.state.component, isA<_TrackedComponent>());
    });

    test(
      'state.context is the capability handle bound to the element (A8)',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final element =
            owner.mountRoot(const _TrackedComponent()) as StatefulElement;
        final context = (element.state as _TrackedState).context;
        // The handle delegates to the element...
        expect(context.elementId, equals(element.elementId));
        // ...but is never the element itself (A8: the separate-handle fork —
        // perception asserted `state.context` WAS the element here).
        expect(context, isNot(same(element)));
        expect(context, isNot(isA<Element>()));
      },
    );
  });

  group('setState() sink', () {
    test('setState() marks element dirty and rebuild runs state.build', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(const _TrackedComponent()) as StatefulElement;
      final state = element.state as _TrackedState;
      state.calls.clear();

      state.setState(() => state.count++);
      expect(state.count, equals(1));
      owner.flush();
      expect(state.calls, equals(['build']));
    });

    test('setState() does not fire didChangeDependencies', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element =
          owner.mountRoot(const _TrackedComponent()) as StatefulElement;
      final state = element.state as _TrackedState;
      state.calls.clear();

      state.setState(() {});
      owner.flush();
      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });

  group('dispose lifecycle', () {
    test('dispose() called on unmount', () {
      final owner = BuildOwner();
      final element =
          owner.mountRoot(const _TrackedComponent()) as StatefulElement;
      final state = element.state as _TrackedState;
      state.calls.clear();

      owner.unmountRoot();
      expect(state.calls, equals(['dispose']));
    });

    test(
      'dispose() called before super.unmount() (element still mounted during dispose)',
      () {
        final owner = BuildOwner();
        final element =
            owner.mountRoot(const _TrackedComponent()) as StatefulElement;

        owner.unmountRoot();
        expect(element.mounted, isFalse);
      },
    );
  });

  group('didChangeDependencies on InheritedComponent change', () {
    test('fires before build when inherited value changes', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedComponent<int>(
                  value: 1,
                  child: const _ReaderComponent(),
                ),
              )
              as InheritedElement<int>;

      final readerElement = root.childElement as StatefulElement;
      final state = readerElement.state as _ReaderState;

      // Initial mount: dcd called with value=1
      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(1));
      state.calls.clear();

      // Update inherited value → triggers dependencyChanged → rebuild with dcd
      root.update(
        InheritedComponent<int>(value: 2, child: const _ReaderComponent()),
      );
      owner.flush();

      expect(state.calls, equals(['dcd', 'build']));
      expect(state.lastValue, equals(2));
    });

    test('does not fire dcd on setState()-driven rebuild', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      final root =
          owner.mountRoot(
                InheritedComponent<int>(
                  value: 1,
                  child: const _ReaderComponent(),
                ),
              )
              as InheritedElement<int>;

      final readerElement = root.childElement as StatefulElement;
      final state = readerElement.state as _ReaderState;
      state.calls.clear();

      // setState()-driven rebuild: no dependency change
      state.setState(() {});
      owner.flush();

      expect(state.calls, equals(['build']));
      expect(state.calls.contains('dcd'), isFalse);
    });
  });

  group('inherited lookups across the State lifecycle', () {
    test(
      'getInheritedValueOfExactType works in initState, dependency-free',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);

        final root =
            owner.mountRoot(
                  InheritedComponent<int>(
                    value: 7,
                    child: const _InitGetComponent(),
                  ),
                )
                as InheritedElement<int>;

        final element = root.childElement as StatefulElement;
        expect((element.state as _InitGetState).initValue, equals(7));
        // A snapshot read: no dependent was registered on the provider.
        expect(root.dependents, isEmpty);
        expect(element.dependencies, isEmpty);
      },
    );

    test('dependOnInheritedValueOfExactType in initState asserts', () {
      final owner = BuildOwner();
      expect(
        () => owner.mountRoot(
          InheritedComponent<int>(
            value: 7,
            child: const _InitDependComponent(),
          ),
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('called from initState'),
          ),
        ),
      );
    });

    test('dependOnInheritedValueOfExactType in dispose asserts', () {
      final owner = BuildOwner();
      owner.mountRoot(
        InheritedComponent<int>(
          value: 7,
          child: const _DisposeDependComponent(),
        ),
      );
      expect(
        owner.unmountRoot,
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            contains('called from dispose'),
          ),
        ),
      );
    });

    test('getInheritedValueOfExactType works in dispose (last read)', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(
                InheritedComponent<int>(
                  value: 9,
                  child: const _DisposeGetComponent(),
                ),
              )
              as InheritedElement<int>;
      final state =
          (root.childElement as StatefulElement).state as _DisposeGetState;

      owner.dispose();
      expect(state.disposeValue, equals(9));
    });
  });
}
