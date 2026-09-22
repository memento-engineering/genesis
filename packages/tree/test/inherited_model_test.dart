// InheritedModel — aspect-scoped inherited dependencies.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

class _S extends Component {
  const _S();
  @override
  _B createElement() => _B(this);
}

class _B extends Element {
  _B(_S super.component);
  bool marked = false;
  @override
  void markNeedsRebuild() {
    marked = true;
    super.markNeedsRebuild();
  }
}

enum _Lane { adrAlignment, coherence }

class _Routing {
  const _Routing({required this.adrAlignment, required this.coherence});
  final String adrAlignment;
  final String coherence;
  @override
  bool operator ==(Object other) =>
      other is _Routing &&
      other.adrAlignment == adrAlignment &&
      other.coherence == coherence;
  @override
  int get hashCode => Object.hash(adrAlignment, coherence);
}

/// A model that reports a change per lane — the committee-routing shape.
class _RoutingModel extends InheritedModel<_Routing, _Lane> {
  const _RoutingModel({required super.value, required super.child});

  @override
  bool updateShouldNotifyDependent(
    covariant _RoutingModel oldComponent,
    Set<_Lane> dependencies,
  ) => dependencies.any(
    (lane) => switch (lane) {
      _Lane.adrAlignment =>
        value.adrAlignment != oldComponent.value.adrAlignment,
      _Lane.coherence => value.coherence != oldComponent.value.coherence,
    },
  );
}

const _v0 = _Routing(adrAlignment: 'opus', coherence: 'sonnet');

InheritedModelElement<_Routing, _Lane> _mountModel(Element parent, _Routing v) {
  final element = _RoutingModel(value: v, child: const _S()).createElement();
  element.mount(parent, 0);
  return element;
}

void main() {
  late BuildOwner owner;
  late _B root;

  setUp(() {
    owner = BuildOwner();
    root = owner.mountRoot(const _S()) as _B;
  });
  tearDown(() => owner.dispose());

  group('aspect-scoped invalidation', () {
    test('only the dependent whose aspect changed is invalidated', () {
      final model = _mountModel(root, _v0);
      final adr = _B(const _S())..mount(model, 0);
      final coh = _B(const _S())..mount(model, 1);
      adr.dependOnInheritedValueOfExactType<_Routing>(
        aspect: _Lane.adrAlignment,
      );
      coh.dependOnInheritedValueOfExactType<_Routing>(aspect: _Lane.coherence);

      model.update(
        const _RoutingModel(
          value: _Routing(adrAlignment: 'haiku', coherence: 'sonnet'),
          child: _S(),
        ),
      );

      expect(adr.marked, isTrue);
      expect(coh.marked, isFalse);
    });

    test('a no-aspect dependent is invalidated by any change', () {
      final model = _mountModel(root, _v0);
      final whole = _B(const _S())..mount(model, 0);
      whole.dependOnInheritedValueOfExactType<_Routing>();

      model.update(
        const _RoutingModel(
          value: _Routing(adrAlignment: 'opus', coherence: 'opus'),
          child: _S(),
        ),
      );

      expect(whole.marked, isTrue);
      expect(model.aspectsOf(whole), isEmpty);
    });

    test('updateShouldNotify false invalidates nobody', () {
      final model = _mountModel(root, _v0);
      final adr = _B(const _S())..mount(model, 0);
      final whole = _B(const _S())..mount(model, 1);
      adr.dependOnInheritedValueOfExactType<_Routing>(
        aspect: _Lane.adrAlignment,
      );
      whole.dependOnInheritedValueOfExactType<_Routing>();

      model.update(const _RoutingModel(value: _v0, child: _S()));

      expect(adr.marked, isFalse);
      expect(whole.marked, isFalse);
    });

    test('the default updateShouldNotifyDependent notifies every aspect', () {
      const component = InheritedModel<String, _Lane>(value: 'a', child: _S());
      final model = component.createElement()..mount(root, 0);
      final dep = _B(const _S())..mount(model, 0);
      dep.dependOnInheritedValueOfExactType<String>(aspect: _Lane.coherence);

      model.update(
        const InheritedModel<String, _Lane>(value: 'b', child: _S()),
      );

      expect(dep.marked, isTrue);
    });

    test('a plain lookup on a model provider resolves the value', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);

      expect(dep.dependOnInheritedValueOfExactType<_Routing>(), _v0);
    });

    test('the BuildContext handle forwards the aspect', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);

      dep.context.dependOnInheritedValueOfExactType<_Routing>(
        aspect: _Lane.coherence,
      );

      expect(model.aspectsOf(dep), {_Lane.coherence});
    });
  });

  group('whole-value stickiness', () {
    test('a no-aspect lookup widens and cannot be re-narrowed', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);
      dep.dependOnInheritedValueOfExactType<_Routing>(
        aspect: _Lane.adrAlignment,
      );
      dep.dependOnInheritedValueOfExactType<_Routing>();
      dep.dependOnInheritedValueOfExactType<_Routing>(aspect: _Lane.coherence);

      expect(model.aspectsOf(dep), isEmpty);

      model.update(
        const _RoutingModel(
          value: _Routing(adrAlignment: 'opus', coherence: 'haiku'),
          child: _S(),
        ),
      );
      expect(dep.marked, isTrue);
    });
  });

  group('loud guards', () {
    test('an aspect against a plain InheritedComponent throws', () {
      final plain = const InheritedComponent<String>(
        value: 'x',
        child: _S(),
      ).createElement()..mount(root, 0);
      final dep = _B(const _S())..mount(plain, 0);

      expect(
        () => dep.dependOnInheritedValueOfExactType<String>(
          aspect: _Lane.coherence,
        ),
        throwsArgumentError,
      );
    });

    test('an aspect of the wrong type throws and registers nothing', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);

      expect(
        () => dep.dependOnInheritedValueOfExactType<_Routing>(
          aspect: 'coherence',
        ),
        throwsArgumentError,
      );
      expect(model.aspectsOf(dep), isNull);
      expect(model.dependents, isNot(contains(dep)));
    });
  });

  group('bookkeeping cleanup', () {
    test('removeDependent clears the aspect entry', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);
      dep.dependOnInheritedValueOfExactType<_Routing>(aspect: _Lane.coherence);

      model.removeDependent(dep);

      expect(model.aspectsOf(dep), isNull);
      expect(model.dependents, isNot(contains(dep)));
      expect(dep.dependencies, isNot(contains(model)));
    });

    test('dependent unmount clears the aspect entry', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);
      dep.dependOnInheritedValueOfExactType<_Routing>(aspect: _Lane.coherence);

      dep.unmount();

      expect(model.aspectsOf(dep), isNull);
      expect(model.dependents, isNot(contains(dep)));
    });

    test('provider unmount clears all aspect entries', () {
      final model = _mountModel(root, _v0);
      final dep = _B(const _S())..mount(model, 0);
      dep.dependOnInheritedValueOfExactType<_Routing>(aspect: _Lane.coherence);

      model.unmount();

      expect(model.aspectsOf(dep), isNull);
      expect(model.dependents, isEmpty);
      expect(dep.dependencies, isNot(contains(model)));
    });
  });

  group('the StatefulElement override forwards the aspect', () {
    test('a State build with an aspect registers exactly that aspect', () {
      final model = _mountModel(root, _v0);
      final host = _AspectComponent().createElement()..mount(model, 0);
      owner.flush();

      expect(model.aspectsOf(host), {_Lane.coherence});
    });
  });
}

class _AspectComponent extends StatefulComponent {
  @override
  State<_AspectComponent> createState() => _AspectState();
}

class _AspectState extends State<_AspectComponent> {
  @override
  Component build(BuildContext context) {
    context.dependOnInheritedValueOfExactType<_Routing>(
      aspect: _Lane.coherence,
    );
    return const _S();
  }
}
