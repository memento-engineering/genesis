import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

/// A stateless perception that builds a fixed seed (the component-root case).
class _Wrap extends StatelessPerception {
  const _Wrap(this.root);
  final Seed root;
  @override
  Seed build(PerceptionContext ctx) => root;
}

void main() {
  late PerceptionOwner owner;
  setUp(() => owner = PerceptionOwner());

  Map<String, Object?> serialize(Seed seed) =>
      serializePerceptionFragment(owner.mountRoot(seed));

  test('serializes Fields as name:value', () {
    final map = serialize(
      const Node(
        'root',
        children: [Field('a', 1), Field('b', 'two'), Field('c', null)],
      ),
    );
    expect(map, {'a': 1, 'b': 'two', 'c': null});
  });

  test('nests child Nodes under their name', () {
    final map = serialize(
      const Node(
        'root',
        children: [
          Field('flat', true),
          Node('child', children: [Field('deep', 42)]),
        ],
      ),
    );
    expect(map, {
      'flat': true,
      'child': {'deep': 42},
    });
  });

  test('unwraps a StatelessPerception component root', () {
    final map = serialize(
      const _Wrap(Node('root', children: [Field('x', 'y')])),
    );
    expect(map, {'x': 'y'});
  });

  test('a non-Node root yields an empty map', () {
    expect(serialize(const _Wrap(Field('lonely', 1))), isEmpty);
  });

  test('preserves child order in the map', () {
    final map = serialize(
      const Node(
        'root',
        children: [Field('first', 1), Field('second', 2), Field('third', 3)],
      ),
    );
    expect(map.keys.toList(), ['first', 'second', 'third']);
  });
}
