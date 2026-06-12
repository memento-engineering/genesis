// Conformance port of lenny perception's inherited_perception_test.dart
// (A10 gate). Behavior expectations unchanged: the markNeedsHarvest funnel
// on PerceptionElement keeps the original invalidation observations valid.
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

class _P extends Perception {
  const _P({this.tag = ''});
  final String tag;
  @override
  _E createElement() => _E(this);
}

class _E extends PerceptionElement {
  _E(_P super.perception);
  bool harvested = false;
  @override
  void markNeedsHarvest() {
    harvested = true;
    super.markNeedsHarvest();
  }
}

InheritedPerceptionElement<String> _mountInherited(
  Branch parent,
  String value,
) {
  final ip = InheritedPerception<String>(value: value, child: _P());
  final el = ip.createBranch();
  el.mount(parent, 0);
  return el;
}

void main() {
  group('InheritedPerception construction', () {
    test('createBranch returns InheritedPerceptionElement<T>', () {
      final ip = InheritedPerception<String>(value: 'x', child: _P());
      expect(ip.createBranch(), isA<InheritedPerceptionElement<String>>());
    });

    test('value and child are preserved', () {
      final child = _P(tag: 'c');
      final ip = InheritedPerception<int>(value: 42, child: child);
      expect(ip.value, 42);
      expect(ip.child, same(child));
    });
  });

  group('dependOnInheritedSeedOfExactType — lookup', () {
    late PerceptionOwner testOwner;
    late _E root;
    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
    });
    tearDown(() => testOwner.dispose());

    test('returns value from direct parent provider', () {
      final ip = _mountInherited(root, 'hello');
      final leaf = _E(_P())..mount(ip, 0);

      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'hello');
    });

    test('returns value from grandparent provider (O(n) walk)', () {
      final ip = _mountInherited(root, 'deep');
      final mid = _E(_P())..mount(ip, 0);
      final leaf = _E(_P())..mount(mid, 0);

      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'deep');
    });

    test('returns null when no ancestor of type T exists', () {
      final leaf = _E(_P())..mount(root, 0);
      expect(leaf.dependOnInheritedSeedOfExactType<String>(), isNull);
    });

    test('skips InheritedPerception<OtherType> and finds correct type', () {
      final intIp = InheritedPerception<int>(value: 7, child: _P());
      final intEl = intIp.createBranch();
      intEl.mount(root, 0);

      final strIp = InheritedPerception<String>(value: 'found', child: _P());
      final strEl = strIp.createBranch();
      strEl.mount(intEl, 0);

      final leaf = _E(_P())..mount(strEl, 0);
      expect(leaf.dependOnInheritedSeedOfExactType<String>(), 'found');
      expect(leaf.dependOnInheritedSeedOfExactType<int>(), 7);
    });
  });

  group('dependency registration', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
    });
    tearDown(() => testOwner.dispose());

    test('lookup registers the caller as a dependent', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(ip.dependents, contains(leaf));
    });

    test('registration is idempotent — two calls, one entry', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(ip.dependents.length, 1);
    });

    test('leaf dependencies contains the provider', () {
      leaf.dependOnInheritedSeedOfExactType<String>();
      expect(leaf.dependencies, contains(ip));
    });
  });

  group('invalidation', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'old');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'value change (updateShouldNotify=true) marks dependent needsHarvest',
      () {
        expect(leaf.harvested, isFalse);
        ip.update(InheritedPerception<String>(value: 'new', child: _P()));
        expect(leaf.harvested, isTrue);
      },
    );

    test(
      'equal value (updateShouldNotify=false) does NOT mark needsHarvest',
      () {
        ip.update(InheritedPerception<String>(value: 'old', child: _P()));
        expect(leaf.harvested, isFalse);
      },
    );

    test('custom updateShouldNotify is honoured', () {
      const nn = _NeverNotify('a');
      final nnEl = nn.createBranch();
      nnEl.mount(root, 1);
      final l2 = _E(_P())..mount(nnEl, 0);
      l2.dependOnInheritedSeedOfExactType<String>();

      nnEl.update(const _NeverNotify('b'));
      expect(l2.harvested, isFalse);
    });
  });

  group('dependent unmount cleanup', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
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

  group('InheritedPerceptionElement unmount cleanup', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedSeedOfExactType<String>();
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

  group('Tree-spine guard', () {
    test('InheritedPerceptionElement is a tree Branch (A12 layering)', () {
      // A12 delta: lenny asserted isA<PerceptionElement> here. Composition
      // elements are tree types now (ADR-0001 Decision 3); only artifact
      // elements extend PerceptionElement.
      final ip = InheritedPerception<String>(value: 'x', child: _P());
      final el = ip.createBranch();
      expect(el, isA<InheritedBranch<String>>());
      expect(el, isA<Branch>());
    });
  });
}

class _NeverNotify extends InheritedPerception<String> {
  const _NeverNotify(String v) : super(value: v, child: const _P());
  @override
  bool updateShouldNotify(_) => false;
}
