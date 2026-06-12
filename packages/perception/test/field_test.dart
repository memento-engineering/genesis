// Field(name, value) — the named value leaf (NEW in the rebuild; fills the
// vocabulary gap the spike ledger identified: Node gave a measurement its
// structure, but no leaf carried the values).
import 'package:perception/perception.dart';
import 'package:test/test.dart';

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
      final el = owner.mountRoot(const Field('n', 1, key: 'a')) as FieldElement;
      expect(
        () => el.update(const Field('n', 1, key: 'b')),
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
                    const Field('a', 1, key: 'ka'),
                    const Field('b', 2, key: 'kb'),
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
            const Field('b', 2, key: 'kb'),
            const Field('a', 1, key: 'ka'),
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
                  Node('reading', children: [const Field('a', 1, key: 'ka')]),
                )
                as NodeElement;

        final fieldEl = el.children[0] as FieldElement;
        el.update(Node('reading', children: [const Field('a', 99, key: 'ka')]));

        expect(el.children[0], same(fieldEl));
        expect(fieldEl.field.value, equals(99));
      },
    );
  });
}
