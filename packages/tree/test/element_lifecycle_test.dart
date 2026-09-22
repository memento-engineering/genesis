// Mounted-element lifecycle coverage for the tree spine.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _S extends Component {
  const _S({this.tag = '', super.key});
  final String tag;
  @override
  _B createElement() => _B(this);
}

class _B extends Element {
  _B(super.component);
  final calls = <String>[];
  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    calls.add('mount');
  }

  @override
  void update(Component newComponent) {
    super.update(newComponent);
    calls.add('update');
  }

  @override
  void unmount() {
    calls.add('unmount');
    super.unmount();
  }
}

void main() {
  group('Element lifecycle', () {
    test('mount: sets mounted=true, elementId non-empty', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S()) as _B;
      expect(element.mounted, isTrue);
      expect(element.elementId, isNotEmpty);
      expect(element.calls, equals(['mount']));
    });

    test('mount: elementId is stable after update', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S()) as _B;
      final id = element.elementId;
      element.update(_S(tag: 'x'));
      expect(element.elementId, equals(id));
    });

    test('mount: throws AssertionError on double-mount', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S()) as _B;
      expect(() => element.mount(null, null), throwsA(isA<AssertionError>()));
    });

    test('mount: throws AssertionError when no owner is available', () {
      final element = _B(_S());
      expect(() => element.mount(null, null), throwsA(isA<AssertionError>()));
    });

    test('unmount: sets mounted=false', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S()) as _B;
      element.unmount();
      expect(element.mounted, isFalse);
      expect(element.calls, equals(['mount', 'unmount']));
    });

    test('unmount: throws AssertionError if already unmounted', () {
      final element = _B(_S());
      expect(() => element.unmount(), throwsA(isA<AssertionError>()));
    });

    test('update: replaces config, records call', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S(tag: 'a')) as _B;
      element.update(_S(tag: 'b'));
      expect((element.component as _S).tag, equals('b'));
      expect(element.calls, equals(['mount', 'update']));
    });

    test('update: throws AssertionError if unmounted', () {
      final element = _B(_S());
      expect(() => element.update(_S()), throwsA(isA<AssertionError>()));
    });

    test('update: throws StateError when canUpdate=false (key mismatch)', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final element = owner.mountRoot(_S(key: ValueKey('a'))) as _B;
      expect(
        () => element.update(_S(key: ValueKey('b'))),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('elementId: owner-scoped issuance', () {
    test(
      'root gets id 0, child mounted via mount() inherits owner and gets id 1',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(_S()) as _B;
        final child = _B(_S())..mount(root, 0);
        expect(root.elementId, equals('0'));
        expect(child.elementId, equals('1'));
      },
    );

    test('two owners issue independent id sequences (both roots get id 0)', () {
      final owner1 = BuildOwner();
      final owner2 = BuildOwner();
      addTearDown(owner1.dispose);
      addTearDown(owner2.dispose);
      final branch1 = owner1.mountRoot(_S()) as _B;
      final branch2 = owner2.mountRoot(_S()) as _B;
      expect(branch1.elementId, equals('0'));
      expect(branch2.elementId, equals('0'));
    });
  });

  group('updateChild (single-child reconciliation)', () {
    late BuildOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    test('null component: unmounts child and returns null', () {
      final child = _B(_S())..mount(root, 0);
      expect(root.updateChild(child, null, 0), isNull);
      expect(child.mounted, isFalse);
      expect(child.calls, containsAllInOrder(['mount', 'unmount']));
    });

    test('null child: mounts fresh element', () {
      final result = root.updateChild(null, _S(tag: 'new'), 0);
      expect(result, isNotNull);
      expect(result!.mounted, isTrue);
    });

    test(
      'canUpdate=true: updates in place, same object, elementId preserved',
      () {
        final child = _B(_S(tag: 'a'))..mount(root, 0);
        final oldId = child.elementId;
        final result = root.updateChild(child, _S(tag: 'b'), 0);
        expect(result, same(child));
        expect(result!.elementId, equals(oldId));
        expect(child.calls, equals(['mount', 'update']));
      },
    );

    test('canUpdate=false (key mismatch): unmounts old, mounts new', () {
      final child = _S(key: ValueKey('x')).createElement()..mount(root, 0);
      final result = root.updateChild(child, _S(key: ValueKey('y')), 0);
      expect(result, isNot(same(child)));
      expect(child.mounted, isFalse);
      expect(result!.mounted, isTrue);
    });
  });

  group('updateChildren (multi-child keyed reconciliation)', () {
    late BuildOwner testOwner;
    late _B root;
    setUp(() {
      testOwner = BuildOwner();
      root = testOwner.mountRoot(_S()) as _B;
    });
    tearDown(() => testOwner.dispose());

    List<_B> mountAll(List<Component> seeds) {
      return seeds.indexed
          .map((r) => seeds[r.$1].createElement() as _B..mount(root, r.$1))
          .toList();
    }

    test('keyed reorder preserves element identity (fork #2)', () {
      final elements = mountAll([
        _S(tag: 'a', key: ValueKey('k-a')),
        _S(tag: 'b', key: ValueKey('k-b')),
        _S(tag: 'c', key: ValueKey('k-c')),
      ]);
      final ids = elements.map((b) => b.elementId).toList();

      final result = root.updateChildren(elements, [
        _S(tag: 'c2', key: ValueKey('k-c')),
        _S(tag: 'a2', key: ValueKey('k-a')),
        _S(tag: 'b2', key: ValueKey('k-b')),
      ]);

      expect(result[0].elementId, equals(ids[2])); // c reused
      expect(result[1].elementId, equals(ids[0])); // a reused
      expect(result[2].elementId, equals(ids[1])); // b reused
      expect(result.every((b) => b.mounted), isTrue);
    });

    test('unmatched key: old unmounted, new element mounted', () {
      final elements = mountAll([
        _S(key: ValueKey('k-a')),
        _S(key: ValueKey('k-b')),
      ]);
      final result = root.updateChildren(elements, [
        _S(key: ValueKey('k-a')),
        _S(key: ValueKey('k-c')),
      ]);

      expect(result[0], same(elements[0]));
      expect(result[1], isNot(same(elements[1])));
      expect(elements[1].mounted, isFalse);
      expect(result[1].mounted, isTrue);
    });

    test('shorter new list: extra old elements are unmounted', () {
      final elements = mountAll([
        _S(key: ValueKey('k-a')),
        _S(key: ValueKey('k-b')),
      ]);
      final result = root.updateChildren(elements, [_S(key: ValueKey('k-a'))]);

      expect(result.length, equals(1));
      expect(result[0], same(elements[0]));
      expect(elements[1].mounted, isFalse);
    });

    test('longer new list: extra seeds are mounted fresh', () {
      final elements = mountAll([_S(key: ValueKey('k-a'))]);
      final result = root.updateChildren(elements, [
        _S(key: ValueKey('k-a')),
        _S(key: ValueKey('k-b')),
      ]);

      expect(result.length, equals(2));
      expect(result[0], same(elements[0]));
      expect(result[1].mounted, isTrue);
    });

    test('unkeyed: elements updated positionally when types match', () {
      final elements = mountAll([_S(tag: 'a'), _S(tag: 'b')]);
      final ids = elements.map((b) => b.elementId).toList();

      final result = root.updateChildren(elements, [
        _S(tag: 'a2'),
        _S(tag: 'b2'),
      ]);

      expect(result[0].elementId, equals(ids[0]));
      expect(result[1].elementId, equals(ids[1]));
    });
  });
}
