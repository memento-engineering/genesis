import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

import 'src/dialogue_fixture.g.dart';

Map<String, Object?> goodAction() => {
  'action': {
    'name': 'set',
    'surfaceId': 'main',
    'sourceComponentId': 'f_name',
    'timestamp': '2026-06-13T00:00:00Z',
    'context': {'value': 'Nicholas'},
  },
};

Map<String, Object?> mountSurfaceMessage() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['f_name'],
      },
      {'id': 'f_name', 'component': 'field', 'name': 'Name', 'value': 'Nico'},
    ],
  },
};

void main() {
  group('parse a v0.9 action message', () {
    test('the wrapped {"action": {...}} envelope', () {
      final event = parseActionEvent(goodAction());
      expect(event.name, 'set');
      expect(event.surfaceId, 'main');
      expect(event.sourceComponentId, 'f_name');
      expect(event.payload, {'value': 'Nicholas'});
      expect(event.timestamp, '2026-06-13T00:00:00Z');
    });

    test('a bare action object (no "action" wrapper)', () {
      final event = parseActionEvent({
        'name': 'press',
        'surfaceId': 's',
        'sourceComponentId': 'b1',
      });
      expect(event.name, 'press');
      expect(event.payload, isEmpty);
      expect(event.timestamp, isNull);
    });
  });

  group('malformed action messages are rejected', () {
    test('missing name', () {
      expect(
        () => parseActionEvent({
          'action': {'surfaceId': 's', 'sourceComponentId': 'c'},
        }),
        throwsA(isA<ActionMessageException>()),
      );
    });

    test('missing sourceComponentId', () {
      expect(
        () => parseActionEvent({
          'action': {'name': 'set', 'surfaceId': 's'},
        }),
        throwsA(isA<ActionMessageException>()),
      );
    });

    test('non-string surfaceId', () {
      expect(
        () => parseActionEvent({
          'action': {'name': 'set', 'surfaceId': 7, 'sourceComponentId': 'c'},
        }),
        throwsA(isA<ActionMessageException>()),
      );
    });

    test('non-object context', () {
      expect(
        () => parseActionEvent({
          'name': 'set',
          'surfaceId': 's',
          'sourceComponentId': 'c',
          'context': 'nope',
        }),
        throwsA(isA<ActionMessageException>()),
      );
    });

    test('non-string timestamp', () {
      expect(
        () => parseActionEvent({
          'name': 'set',
          'surfaceId': 's',
          'sourceComponentId': 'c',
          'timestamp': 12345,
        }),
        throwsA(isA<ActionMessageException>()),
      );
    });

    test('every action reject is a DialogueException', () {
      expect(
        () => parseActionEvent('not-a-map'),
        throwsA(isA<DialogueException>()),
      );
    });
  });

  group('parsing an action mutates no tree (routing is consent\'s job)', () {
    test('the live surface is untouched by parseActionEvent', () {
      final surface = DialogueSurface(registry: componentRegistry);
      final root =
          surface.mount(parseUpdateComponents(mountSurfaceMessage()))
              as NodeElement;
      final fieldBefore =
          root.children.single as FieldElement; // f_name value "Nico"

      // Parse a (valid) action that *targets* the mounted field. dialogue
      // produces the typed event only — it never routes or applies it.
      final event = parseActionEvent(goodAction());
      expect(event.sourceComponentId, 'f_name');

      // No mutation: same Branch, same value, still mounted.
      expect(identical(root.children.single, fieldBefore), isTrue);
      expect(fieldBefore.field.value, 'Nico');
      expect(fieldBefore.mounted, isTrue);
    });
  });
}
