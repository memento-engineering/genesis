import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

enum _Status { ready }

final class _Unsupported {
  const _Unsupported();

  @override
  String toString() => 'unsupported';
}

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

  TreeSnapshot project(Seed seed, {required DateTime projectedAt}) =>
      projectPerceptionTree(owner.mountRoot(seed), projectedAt: projectedAt);

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

  test('projects every pinned field variant at info severity', () {
    final timestamp = DateTime.parse('2026-08-01T03:00:00-05:00');
    final snapshot = project(
      Node(
        'root',
        key: const Key('root-key'),
        children: [
          const Field('string', 'value'),
          const Field('int', 7),
          const Field('double', 2.5),
          const Field('flag', true),
          const Field('enum', _Status.ready),
          const Field('duration', Duration(microseconds: 42)),
          Field('timestamp', timestamp),
          const Field('null', null),
          const Field('collection', <int>[1, 2]),
          const Field('unsupported', _Unsupported()),
          const Node('child', children: [Field('nested', 'yes')]),
        ],
      ),
      projectedAt: timestamp,
    );

    expect(snapshot.contractVersion, 1);
    expect(snapshot.projectedAt, DateTime.utc(2026, 8, 1, 8));
    expect(snapshot.root.seedType, 'Node');
    expect(snapshot.root.id, isNotEmpty);
    expect(snapshot.root.key, "[ValueKey<String> <'root-key'>]");
    expect(snapshot.root.children, hasLength(1));
    expect(snapshot.root.children.single.seedType, 'Node');
    expect(snapshot.root.properties, [
      const DiagnosticsProperty.string(
        name: 'string',
        level: DiagnosticsLevel.info,
        value: 'value',
      ),
      const DiagnosticsProperty.int(
        name: 'int',
        level: DiagnosticsLevel.info,
        value: 7,
      ),
      const DiagnosticsProperty.double(
        name: 'double',
        level: DiagnosticsLevel.info,
        value: 2.5,
      ),
      const DiagnosticsProperty.flag(
        name: 'flag',
        level: DiagnosticsLevel.info,
        value: true,
      ),
      const DiagnosticsProperty.enumValue(
        name: 'enum',
        level: DiagnosticsLevel.info,
        value: 'ready',
        enumType: '_Status',
      ),
      const DiagnosticsProperty.duration(
        name: 'duration',
        level: DiagnosticsLevel.info,
        value: Duration(microseconds: 42),
      ),
      DiagnosticsProperty.timestamp(
        name: 'timestamp',
        level: DiagnosticsLevel.info,
        value: timestamp,
      ),
      const DiagnosticsProperty.object(
        name: 'null',
        level: DiagnosticsLevel.info,
        properties: [
          DiagnosticsProperty.string(
            name: 'value',
            level: DiagnosticsLevel.info,
            value: 'null',
          ),
        ],
      ),
      const DiagnosticsProperty.object(
        name: 'collection',
        level: DiagnosticsLevel.info,
        properties: [
          DiagnosticsProperty.string(
            name: 'value',
            level: DiagnosticsLevel.info,
            value: '[1, 2]',
          ),
        ],
      ),
      const DiagnosticsProperty.object(
        name: 'unsupported',
        level: DiagnosticsLevel.info,
        properties: [
          DiagnosticsProperty.string(
            name: 'value',
            level: DiagnosticsLevel.info,
            value: 'unsupported',
          ),
        ],
      ),
    ]);
    expect(
      snapshot.root.properties.whereType<DiagnosticsReferenceProperty>(),
      isEmpty,
    );
  });

  test('projected snapshot round-trips through version-1 JSON', () {
    final projectedAt = DateTime.utc(2026, 8, 1, 9);
    final snapshot = project(
      const Node(
        'root',
        children: [
          Field('answer', 42),
          Node('child', children: [Field('state', _Status.ready)]),
        ],
      ),
      projectedAt: projectedAt,
    );
    expect(TreeSnapshot.fromJson(snapshot.toJson()), snapshot);
  });

  test('typed projection unwraps a component root', () {
    final snapshot = project(
      const _Wrap(Node('root', children: [Field('x', 'y')])),
      projectedAt: DateTime.utc(2026, 8, 1),
    );
    expect(snapshot.root.properties.single.name, 'x');
  });

  test('typed projection rejects a non-Node root loudly', () {
    final root = owner.mountRoot(const _Wrap(Field('lonely', 1)));
    expect(
      () => projectPerceptionTree(root, projectedAt: DateTime.utc(2026, 8, 1)),
      throwsArgumentError,
    );
  });
}
