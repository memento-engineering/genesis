import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:test/test.dart';

Map<String, Object?> envelopeWith(List<Object?> components) => {
  'version': 'v0.9',
  'updateComponents': {'surfaceId': 'main', 'components': components},
};

void main() {
  group('A2UI v0.9 fidelity', () {
    test('the updateComponents key is accepted', () {
      final u = parseUpdateComponents(
        envelopeWith([
          {'id': 'root', 'component': 'node', 'name': 'n'},
        ]),
      );
      expect(u.surfaceId, 'main');
    });

    test('a v0.8 surfaceUpdate-keyed message is rejected', () {
      // Same body, wrong outer key — strict version is the first gate, but
      // even with a correct version the missing updateComponents body throws.
      final v08 = {
        'version': 'v0.9',
        'surfaceUpdate': {'surfaceId': 'main', 'components': <Object?>[]},
      };
      expect(
        () => parseUpdateComponents(v08),
        throwsA(isA<MissingUpdateComponentsException>()),
      );
    });

    test('root is identified by id == "root" (no rootId field)', () {
      final u = parseUpdateComponents(
        envelopeWith([
          {
            'id': 'root',
            'component': 'node',
            'name': 'r',
            'children': ['leaf'],
          },
          {'id': 'leaf', 'component': 'field', 'name': 'n', 'value': 'v'},
        ]),
      );
      // The parsed instances carry no rootId notion; root is the id == "root".
      expect(u.components.any((c) => c.id == rootComponentId), isTrue);
    });

    test('no rootId field is emitted on serialize', () {
      final json = parseUpdateComponents(
        envelopeWith([
          {'id': 'root', 'component': 'node', 'name': 'r'},
        ]),
      ).toJson();
      final body = json['updateComponents'] as Map;
      expect(body.containsKey('rootId'), isFalse);
    });
  });

  group('version strictness (strict — pure v0.9)', () {
    test('missing version is rejected', () {
      expect(
        () => parseUpdateComponents({
          'updateComponents': {'surfaceId': 's', 'components': <Object?>[]},
        }),
        throwsA(isA<UnsupportedVersionException>()),
      );
    });

    test('a v0.8 version string is rejected', () {
      expect(
        () => parseUpdateComponents({
          'version': 'v0.8',
          'updateComponents': {'surfaceId': 's', 'components': <Object?>[]},
        }),
        throwsA(isA<UnsupportedVersionException>()),
      );
    });
  });

  group('envelope-level structural rejection', () {
    test('missing updateComponents body throws', () {
      expect(
        () => parseUpdateComponents({'version': 'v0.9'}),
        throwsA(isA<MissingUpdateComponentsException>()),
      );
    });

    test('non-string surfaceId throws', () {
      expect(
        () => parseUpdateComponents({
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 7, 'components': <Object?>[]},
        }),
        throwsA(isA<EnvelopeFieldException>()),
      );
    });

    test('non-list components throws', () {
      expect(
        () => parseUpdateComponents({
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 's', 'components': 'nope'},
        }),
        throwsA(isA<EnvelopeFieldException>()),
      );
    });

    test('component missing id throws', () {
      expect(
        () => parseUpdateComponents(
          envelopeWith([
            {'component': 'node', 'name': 'n'},
          ]),
        ),
        throwsA(isA<MalformedComponentException>()),
      );
    });

    test('component missing component discriminator throws', () {
      expect(
        () => parseUpdateComponents(
          envelopeWith([
            {'id': 'root', 'name': 'n'},
          ]),
        ),
        throwsA(isA<MalformedComponentException>()),
      );
    });

    test('non-object component entry throws', () {
      expect(
        () => parseUpdateComponents(envelopeWith(['not-an-object'])),
        throwsA(isA<MalformedComponentException>()),
      );
    });

    test('non-string-list children throws', () {
      expect(
        () => parseUpdateComponents(
          envelopeWith([
            {
              'id': 'root',
              'component': 'node',
              'name': 'n',
              'children': [1, 2],
            },
          ]),
        ),
        throwsA(isA<EnvelopeFieldException>()),
      );
    });

    test('duplicate component id throws with both indices', () {
      expect(
        () => parseUpdateComponents(
          envelopeWith([
            {'id': 'root', 'component': 'node', 'name': 'a'},
            {'id': 'root', 'component': 'node', 'name': 'b'},
          ]),
        ),
        throwsA(
          isA<DuplicateEnvelopeIdException>()
              .having((e) => e.firstIndex, 'firstIndex', 0)
              .having((e) => e.secondIndex, 'secondIndex', 1),
        ),
      );
    });

    test('every reject is a DialogueException (one feedback union)', () {
      expect(
        () => parseUpdateComponents({'version': 'v0.8'}),
        throwsA(isA<DialogueException>()),
      );
    });
  });
}
