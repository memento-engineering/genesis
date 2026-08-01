// Field(name, value) — the named value leaf (NEW in the rebuild; fills the
// vocabulary gap the spike ledger identified: Node gave a measurement its
// structure, but no leaf carried the values).
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

enum _Status { ready }

final class _Unsupported {
  const _Unsupported();

  @override
  String toString() => 'unsupported';
}

void main() {
  group('Field construction', () {
    test('createElement returns FieldElement', () {
      expect(const Field('n', 1).createElement(), isA<FieldElement>());
    });

    test('name and value stored', () {
      const f = Field('temperature', 21.5);
      expect(f.name, equals('temperature'));
      expect(f.value, equals(21.5));
    });

    test('null is a legal measurement value', () {
      const f = Field('absent', null);
      expect(f.value, isNull);
    });

    test('describes every pinned value variant as one domain property', () {
      final timestamp = DateTime.parse('2026-08-01T03:00:00-05:00');
      final cases = <(Field, DiagnosticsProperty)>[
        (
          const Field('string', 'value'),
          const DiagnosticsProperty.string(
            name: 'string',
            level: DiagnosticsLevel.info,
            value: 'value',
          ),
        ),
        (
          const Field('int', 7),
          const DiagnosticsProperty.int(
            name: 'int',
            level: DiagnosticsLevel.info,
            value: 7,
          ),
        ),
        (
          const Field('double', 2.5),
          const DiagnosticsProperty.double(
            name: 'double',
            level: DiagnosticsLevel.info,
            value: 2.5,
          ),
        ),
        (
          const Field('flag', true),
          const DiagnosticsProperty.flag(
            name: 'flag',
            level: DiagnosticsLevel.info,
            value: true,
          ),
        ),
        (
          const Field('enum', _Status.ready),
          const DiagnosticsProperty.enumValue(
            name: 'enum',
            level: DiagnosticsLevel.info,
            value: 'ready',
            enumType: '_Status',
          ),
        ),
        (
          const Field('duration', Duration(microseconds: 42)),
          const DiagnosticsProperty.duration(
            name: 'duration',
            level: DiagnosticsLevel.info,
            value: Duration(microseconds: 42),
          ),
        ),
        (
          Field('timestamp', timestamp),
          DiagnosticsProperty.timestamp(
            name: 'timestamp',
            level: DiagnosticsLevel.info,
            value: timestamp,
          ),
        ),
        (
          const Field('null', null),
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
        ),
        (
          const Field('collection', <int>[1, 2]),
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
        ),
        (
          const Field('unsupported', _Unsupported()),
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
        ),
      ];

      for (final (field, expected) in cases) {
        final properties = <DiagnosticsProperty>[];
        field.debugFillProperties(properties);
        expect(properties, [expected], reason: field.name);
      }
    });
  });

  group('FieldElement mount', () {
    test('mounts as a leaf: mounted=true, no children visited', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(const Field('n', 1)) as FieldElement;
      expect(el.mounted, isTrue);

      final visited = <Branch>[];
      el.visitChildren(visited.add);
      expect(visited, isEmpty);
    });

    test('field getter exposes the typed config', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(const Field('n', 'v')) as FieldElement;
      expect(el.field.name, equals('n'));
      expect(el.field.value, equals('v'));
    });
  });

  group('FieldElement update', () {
    test('update in place preserves identity; new value visible (A9)', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(const Field('n', 1)) as FieldElement;
      final id = el.perceptionId;

      el.update(const Field('n', 2));

      expect(el.perceptionId, equals(id));
      expect(el.field.value, equals(2));
    });

    test('update throws AssertionError when canUpdate=false (key change)', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(const Field('n', 1, key: ValueKey('a')))
              as FieldElement;
      expect(
        () => el.update(const Field('n', 1, key: ValueKey('b'))),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Field inside Node', () {
    test('fields mount as node children', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(
                Node(
                  'reading',
                  children: [const Field('a', 1), const Field('b', 2)],
                ),
              )
              as NodeElement;

      expect(el.children, everyElement(isA<FieldElement>()));
      expect(el.children.every((c) => c.mounted), isTrue);
    });

    test('keyed reorder preserves FieldElement identity', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el =
          owner.mountRoot(
                Node(
                  'reading',
                  children: [
                    const Field('a', 1, key: ValueKey('ka')),
                    const Field('b', 2, key: ValueKey('kb')),
                  ],
                ),
              )
              as NodeElement;

      final idA = el.children[0].branchId;
      final idB = el.children[1].branchId;

      el.update(
        Node(
          'reading',
          children: [
            const Field('b', 2, key: ValueKey('kb')),
            const Field('a', 1, key: ValueKey('ka')),
          ],
        ),
      );

      expect(el.children[0].branchId, equals(idB));
      expect(el.children[1].branchId, equals(idA));
    });

    test(
      'node update swaps field values in place (A9: hook runs on update)',
      () {
        final owner = PerceptionOwner();
        addTearDown(owner.dispose);
        final el =
            owner.mountRoot(
                  Node(
                    'reading',
                    children: [const Field('a', 1, key: ValueKey('ka'))],
                  ),
                )
                as NodeElement;

        final fieldEl = el.children[0] as FieldElement;
        el.update(
          Node(
            'reading',
            children: [const Field('a', 99, key: ValueKey('ka'))],
          ),
        );

        expect(el.children[0], same(fieldEl));
        expect(fieldEl.field.value, equals(99));
      },
    );
  });
}
