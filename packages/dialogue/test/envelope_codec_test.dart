import 'dart:convert';

import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:test/test.dart';

/// A known-good v0.9 envelope: root node + mixed node/field children,
/// exercising props at top level and `children` as an ordered id array.
Map<String, Object?> goodEnvelope() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['f_name', 'n_addr', 'f_email'],
      },
      {'id': 'f_name', 'component': 'field', 'name': 'Name', 'value': 'Nico'},
      {
        'id': 'n_addr',
        'component': 'node',
        'name': 'address',
        'children': ['f_street'],
      },
      {
        'id': 'f_street',
        'component': 'field',
        'name': 'Street',
        'value': '1 Main',
      },
      {
        'id': 'f_email',
        'component': 'field',
        'name': 'Email',
        'value': 'a@b.c',
      },
    ],
  },
};

void main() {
  group('codec round-trip (lossless both directions)', () {
    test('parse(json) -> toJson() is structurally equal to json', () {
      final json = goodEnvelope();
      final parsed = parseUpdateComponents(json);
      final reEmitted = parsed.toJson();
      // Compare via canonical JSON encode/decode to ignore key order.
      expect(jsonDecode(jsonEncode(reEmitted)), jsonDecode(jsonEncode(json)));
    });

    test('toJson(parse(json)) is stable (a second pass is identical)', () {
      final json = goodEnvelope();
      final once = parseUpdateComponents(json).toJson();
      final twice = parseUpdateComponents(once).toJson();
      expect(jsonEncode(twice), jsonEncode(once));
    });

    test('typed fields land on UpdateComponents', () {
      final u = parseUpdateComponents(goodEnvelope());
      expect(u.surfaceId, 'main');
      expect(u.components, hasLength(5));
      final root = u.components.first;
      expect(root.id, 'root');
      expect(root.type, 'node');
      expect(root.props, {'name': 'form'});
      expect(root.childIds, ['f_name', 'n_addr', 'f_email']);
      final field = u.components[1];
      expect(field.id, 'f_name');
      expect(field.type, 'field');
      expect(field.props, {'name': 'Name', 'value': 'Nico'});
      expect(field.childIds, isEmpty);
    });

    test('absent and empty children round-trip identically', () {
      // A leaf with no children re-emits with no `children` key.
      final json = {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's',
          'components': [
            {'id': 'root', 'component': 'field', 'name': 'n', 'value': 'v'},
          ],
        },
      };
      final reEmitted = parseUpdateComponents(json).toJson();
      final components =
          ((reEmitted['updateComponents'] as Map)['components'] as List);
      expect((components.first as Map).containsKey('children'), isFalse);
    });

    test('props survive of every JSON scalar kind', () {
      // The codec is prop-type-agnostic; non-string props round-trip verbatim
      // (registry validation is a separate, build-time concern).
      final json = {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's',
          'components': [
            {
              'id': 'root',
              'component': 'widget',
              'count': 3,
              'ratio': 1.5,
              'on': true,
              'label': 'hi',
              'tags': ['a', 'b'],
            },
          ],
        },
      };
      final parsed = parseUpdateComponents(json);
      expect(parsed.components.single.props, {
        'count': 3,
        'ratio': 1.5,
        'on': true,
        'label': 'hi',
        'tags': ['a', 'b'],
      });
      expect(
        jsonDecode(jsonEncode(parsed.toJson())),
        jsonDecode(jsonEncode(json)),
      );
    });
  });
}
