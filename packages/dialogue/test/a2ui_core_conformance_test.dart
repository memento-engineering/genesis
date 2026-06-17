// Conformance/interop check against flutter/genui's `a2ui_core` (register A26:
// interoperate, don't fork). Asserts genesis_dialogue's wire round-trips with
// the EXACT JSON shapes a2ui_core emits — WITHOUT depending on a2ui_core (a
// `0.0.1-wip` package). The shapes below are mirrored from a2ui_core
// (flutter/genui @ main, lib/src/core/messages.dart, verified 2026-06-14):
//
//   UpdateComponentsMessage.toJson() =>
//     {'version': v, 'updateComponents': {'surfaceId': s, 'components': [...]}}
//   A2uiMessage.fromJson requires version 'v0.9' + exactly ONE body key from
//     {createSurface, updateComponents, updateDataModel, deleteSurface};
//     _processUpdateComponents reads compJson['id'] and compJson['component'].
//   A2uiClientAction.toJson() =>
//     {'name','surfaceId','sourceComponentId','timestamp'(ISO-8601),'context'}
import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

import 'src/dialogue_fixture.g.dart';

/// a2ui_core's `A2uiMessage` body discriminator keys (mirrored, not imported).
const _a2uiBodyKeys = {
  'createSurface',
  'updateComponents',
  'updateDataModel',
  'deleteSurface',
};

void main() {
  group('a2ui_core conformance (interop, no genui dependency — A26)', () {
    test('parses an a2ui_core UpdateComponentsMessage.toJson() shape', () {
      final wire = {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 'main',
          'components': [
            {
              'id': 'root',
              'component': 'node',
              'name': 'form',
              'children': ['f1'],
            },
            {'id': 'f1', 'component': 'field', 'name': 'Name', 'value': 'Nico'},
          ],
        },
      };
      final surface = DialogueSurface(registry: componentRegistry);
      final root = surface.mount(parseUpdateComponents(wire));
      expect(root, isA<NodeElement>());
      expect((root as NodeElement).children.single.key, const ValueKey('f1'));
    });

    test('our toJson() is a shape a2ui_core A2uiMessage.fromJson accepts', () {
      final msg = parseUpdateComponents({
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 'main',
          'components': [
            {
              'id': 'root',
              'component': 'node',
              'name': 'form',
              'children': ['f1'],
            },
            {'id': 'f1', 'component': 'field', 'name': 'N', 'value': 'V'},
          ],
        },
      });
      final json = msg.toJson();

      // version 'v0.9' + EXACTLY one recognized body key.
      expect(json['version'], 'v0.9');
      expect(_a2uiBodyKeys.where(json.containsKey).toList(), [
        'updateComponents',
      ]);

      final body = json['updateComponents']! as Map<String, Object?>;
      expect(body['surfaceId'], 'main');
      expect(body['components'], isA<List<Object?>>());
      // Each component carries the fields a2ui_core reads off it.
      for (final c in body['components']! as List<Object?>) {
        final m = c! as Map<String, Object?>;
        expect(m['id'], isA<String>());
        expect(m['component'], isA<String>());
      }
    });

    test('parses an a2ui_core A2uiClientAction.toJson() shape', () {
      final wire = {
        'name': 'press',
        'surfaceId': 'main',
        'sourceComponentId': 'f1',
        'timestamp': '2026-06-14T10:00:00.000Z',
        'context': {'amount': 1},
      };
      final event = parseActionEvent(wire);
      expect(event.name, 'press');
      expect(event.surfaceId, 'main');
      expect(event.sourceComponentId, 'f1');
      expect(event.timestamp, '2026-06-14T10:00:00.000Z');
      expect(event.payload, {'amount': 1});
    });
  });
}
