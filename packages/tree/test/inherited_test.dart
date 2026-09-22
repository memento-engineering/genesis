// Port of perception's inherited_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _S extends Component {
  const _S({this.tag = ''});
  final String tag;
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

InheritedElement<String> _mountInherited(Element parent, String value) {
  final ip = InheritedComponent<String>(value: value, child: _S());
  final element = ip.createElement();
  element.mount(parent, 0);
  return element;
}

void main() {
  group('InheritedComponent construction', () {
    test('createElement returns InheritedElement<T>', () {
      final ip = InheritedComponent<String>(value: 'x', child: _S());
      expect(ip.createElement(), isA<InheritedElement<String>>());
    });

    test('value and child are preserved', () {
      final child = _S(tag: 'c');
      final ip = InheritedComponent<int>(value: 42, child: child);
      expect(ip.value, 42);
      expect(ip.child, same(child));
    });
  });

  group('dependOnInheritedValueOfExactType — lookup', () {
    late BuildOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    test('returns value from direct parent provider', () {
      final ip = _mountInherited(root, 'hello');
      final leaf = _B(_S())..mount(ip, 0);

      expect(leaf.dependOnInheritedValueOfExactType<String>(), 'hello');
    });

    test('returns value from grandparent provider (O(n) walk)', () {
      final ip = _mountInherited(root, 'deep');
      final mid = _B(_S())..mount(ip, 0);
      final leaf = _B(_S())..mount(mid, 0);

      expect(leaf.dependOnInheritedValueOfExactType<String>(), 'deep');
    });

    test('returns null when no ancestor of type T exists', () {
      final leaf = _B(_S())..mount(root, 0);
      expect(leaf.dependOnInheritedValueOfExactType<String>(), isNull);
    });

    test('skips InheritedComponent<OtherType> and finds correct type', () {
      final intIp = InheritedComponent<int>(value: 7, child: _S());
      final intElement = intIp.createElement();
      intElement.mount(root, 0);

      final strIp = InheritedComponent<String>(value: 'found', child: _S());
      final strElement = strIp.createElement();
      strElement.mount(intElement, 0);

      final leaf = _B(_S())..mount(strElement, 0);
      expect(leaf.dependOnInheritedValueOfExactType<String>(), 'found');
      expect(leaf.dependOnInheritedValueOfExactType<int>(), 7);
    });
  });

  group('getInheritedValueOfExactType — dependency-free lookup', () {
    late BuildOwner testOwner;
    late _B root;
    late InheritedElement<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'snap');
      leaf = _B(_S())..mount(ip, 0);
    });
    tearDown(() => testOwner.dispose());

    test('returns the nearest ancestor value', () {
      expect(leaf.getInheritedValueOfExactType<String>(), 'snap');
    });

    test('returns value through intermediate elements (same walk)', () {
      final deep = _B(_S())..mount(leaf, 0);
      expect(deep.getInheritedValueOfExactType<String>(), 'snap');
    });

    test('returns null when no ancestor of type T exists', () {
      expect(leaf.getInheritedValueOfExactType<int>(), isNull);
    });

    test('does NOT register the caller as a dependent (either side)', () {
      leaf.getInheritedValueOfExactType<String>();
      expect(ip.dependents, isEmpty);
      expect(leaf.dependencies, isEmpty);
    });

    test('value change does NOT mark a get-only reader', () {
      leaf.getInheritedValueOfExactType<String>();
      ip.update(InheritedComponent<String>(value: 'changed', child: _S()));
      expect(leaf.marked, isFalse);
    });

    test('get after dependOn leaves the existing dependency intact', () {
      leaf.dependOnInheritedValueOfExactType<String>();
      leaf.getInheritedValueOfExactType<String>();
      expect(ip.dependents, contains(leaf));
      expect(leaf.dependencies, contains(ip));
    });
  });

  group('dependency registration', () {
    late BuildOwner testOwner;
    late _B root;
    late InheritedElement<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
    });
    tearDown(() => testOwner.dispose());

    test('lookup registers the caller as a dependent', () {
      leaf.dependOnInheritedValueOfExactType<String>();
      expect(ip.dependents, contains(leaf));
    });

    test('registration is idempotent — two calls, one entry', () {
      leaf.dependOnInheritedValueOfExactType<String>();
      leaf.dependOnInheritedValueOfExactType<String>();
      expect(ip.dependents.length, 1);
    });

    test('leaf dependencies contains the provider', () {
      leaf.dependOnInheritedValueOfExactType<String>();
      expect(leaf.dependencies, contains(ip));
    });
  });

  group('invalidation', () {
    late BuildOwner testOwner;
    late _B root;
    late InheritedElement<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'old');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedValueOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'value change (updateShouldNotify=true) marks dependent needsRebuild',
      () {
        expect(leaf.marked, isFalse);
        ip.update(InheritedComponent<String>(value: 'new', child: _S()));
        expect(leaf.marked, isTrue);
      },
    );

    test(
      'equal value (updateShouldNotify=false) does NOT mark needsRebuild',
      () {
        ip.update(InheritedComponent<String>(value: 'old', child: _S()));
        expect(leaf.marked, isFalse);
      },
    );

    test('custom updateShouldNotify is honoured', () {
      const nn = _NeverNotify('a');
      final nnElement = nn.createElement();
      nnElement.mount(root, 1);
      final leaf2 = _B(_S())..mount(nnElement, 0);
      leaf2.dependOnInheritedValueOfExactType<String>();

      nnElement.update(const _NeverNotify('b'));
      expect(leaf2.marked, isFalse);
    });
  });

  group('dependent unmount cleanup', () {
    late BuildOwner testOwner;
    late _B root;
    late InheritedElement<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedValueOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test('leaf unmount removes it from provider dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      leaf.unmount();
      expect(ip.dependents, isNot(contains(leaf)));
    });

    test('leaf unmount clears its own dependencies (no leak)', () {
      expect(leaf.dependencies, contains(ip));
      leaf.unmount();
      expect(leaf.dependencies, isEmpty);
    });
  });

  group('InheritedElement unmount cleanup', () {
    late BuildOwner testOwner;
    late _B root;
    late InheritedElement<String> ip;
    late _B leaf;

    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
      ip = _mountInherited(root, 'v');
      leaf = _B(_S())..mount(ip, 0);
      leaf.dependOnInheritedValueOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'provider unmount removes itself from dependent dependencies (no leak)',
      () {
        expect(leaf.dependencies, contains(ip));
        ip.unmount();
        expect(leaf.dependencies, isNot(contains(ip)));
      },
    );

    test('provider unmount clears its own dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      ip.unmount();
      expect(ip.dependents, isEmpty);
    });
  });

  group('Pure-Dart guard', () {
    test('InheritedElement is a Element', () {
      final ip = InheritedComponent<String>(value: 'x', child: _S());
      final element = ip.createElement();
      expect(element, isA<Element>());
    });
  });
}

class _NeverNotify extends InheritedComponent<String> {
  const _NeverNotify(String v) : super(value: v, child: const _S());
  @override
  bool updateShouldNotify(_) => false;
}
