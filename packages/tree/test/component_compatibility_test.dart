// ignore_for_file: deprecated_member_use

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

class _CanonicalComponent extends Component {
  const _CanonicalComponent({super.key});

  @override
  _CanonicalElement createElement() => _CanonicalElement(this);
}

class _CanonicalElement extends Element {
  _CanonicalElement(super.component);
}

class _LegacySeed extends Seed {
  const _LegacySeed({super.key});

  @override
  _LegacyBranch createBranch() => _LegacyBranch(this);
}

class _LegacyBranch extends Branch {
  _LegacyBranch(super.seed);
}

class _LegacyStatelessSeed extends StatelessSeed {
  const _LegacyStatelessSeed();

  @override
  Seed build(TreeContext context) => const _CanonicalComponent();
}

void main() {
  test('deprecated type aliases preserve identity and subclassing', () {
    expect(Seed, Component);
    expect(Branch, Element);
    expect(TreeContext, BuildContext);
    expect(TreeOwner, BuildOwner);
    expect(ComponentBranch, BuildableElement);
    expect(StatelessSeed, StatelessComponent);
    expect(StatefulSeed, StatefulComponent);
    expect(InheritedSeed<Object>, InheritedComponent<Object>);
    expect(MultiChildSeed, MultiChildComponent);
    expect(Sprout, HookComponent);
    expect(const _LegacySeed(), isA<Component>());
    expect(_LegacyBranch(const _LegacySeed()), isA<Element>());
  });

  test('old and new factory overrides dispatch through both spellings', () {
    const key = ValueKey<String>('same');
    const canonical = _CanonicalComponent(key: key);
    const legacy = _LegacySeed(key: key);

    expect(canonical.createElement(), isA<_CanonicalElement>());
    expect(canonical.createBranch(), isA<_CanonicalElement>());
    expect(legacy.createElement(), isA<_LegacyBranch>());
    expect(legacy.createBranch(), isA<_LegacyBranch>());
    expect(canonical.createElement().runtimeType, _CanonicalElement);
    expect(legacy.createElement().runtimeType, _LegacyBranch);
    expect(canonical.key, key);
    expect(legacy.key, key);
  });

  test('legacy members forward to the canonical implementation', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const _LegacyStatelessSeed());

    expect(root.seed, same(root.component));
    expect(root.branchId, root.elementId);
    expect(root.context.branchId, root.context.elementId);
    expect(
      root.context.getInheritedSeedOfExactType<String>(),
      root.context.getInheritedValueOfExactType<String>(),
    );
    expect(
      root.context.dependOnInheritedSeedOfExactType<String>(),
      root.context.dependOnInheritedValueOfExactType<String>(),
    );
    expect(owner.flush(), isEmpty);
  });

  test('canonical and legacy canUpdate calls share key semantics', () {
    const first = _CanonicalComponent(key: ValueKey<String>('id'));
    const second = _CanonicalComponent(key: ValueKey<String>('id'));
    const other = _CanonicalComponent(key: ValueKey<String>('other'));

    expect(Component.canUpdate(first, second), isTrue);
    expect(Seed.canUpdate(first, second), isTrue);
    expect(Component.canUpdate(first, other), isFalse);
  });
}
