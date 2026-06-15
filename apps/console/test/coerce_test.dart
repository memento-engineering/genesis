import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:genesis_console/genesis_console.dart';
// coercedIntProps is an internal invariant surface, not part of the barrel.
import 'package:genesis_console/src/agent/coerce.dart' show coercedIntProps;
import 'package:test/test.dart';

void main() {
  // Pull the components list back out of the wrapped message for assertions.
  List<Map<String, Object?>> componentsOf(Map<String, Object?> message) {
    final uc = message['updateComponents'] as Map<String, Object?>;
    return (uc['components'] as List<Object?>).cast<Map<String, Object?>>();
  }

  test(
    'a clean components array is wrapped with version and a screen root',
    () {
      final args = jsonEncode({
        'components': [
          {
            'id': 'content',
            'component': 'box',
            'title': 'Demo',
            'children': ['c1'],
          },
          {'id': 'c1', 'component': 'counter', 'label': 'Apples', 'start': 3},
        ],
      });
      final message = toUpdateComponents(args);
      expect(message['version'], 'v0.9');
      final components = componentsOf(message);
      final root = components.first;
      expect(root['id'], 'root');
      expect(root['component'], 'screen');
      expect(root['children'], ['content']);
      // The model's components follow the synthesised root, in order.
      expect(components[1]['id'], 'content');
      expect(components[2]['id'], 'c1');
    },
  );

  test('a stringified components value is reparsed', () {
    // The exact shape qwen emitted live: components as an escaped JSON string.
    final args = jsonEncode({
      'components': jsonEncode([
        {
          'id': 'content',
          'component': 'box',
          'title': 'Demo',
          'children': ['t1'],
        },
        {'id': 't1', 'component': 'text', 'content': 'hi'},
      ]),
    });
    final components = componentsOf(toUpdateComponents(args));
    expect(components.map((c) => c['id']), ['root', 'content', 't1']);
  });

  test('a numeric-string start is coerced to an int', () {
    final args = jsonEncode({
      'components': [
        {
          'id': 'content',
          'component': 'box',
          'title': 'A',
          'children': ['c1'],
        },
        {'id': 'c1', 'component': 'counter', 'label': 'A', 'start': '7'},
      ],
    });
    final counter = componentsOf(toUpdateComponents(args))[2];
    expect(counter['start'], 7);
    expect(counter['start'], isA<int>());
  });

  test('missing "content" container throws descriptively', () {
    final args = jsonEncode({
      'components': [
        {'id': 'box1', 'component': 'box', 'title': 'X'},
      ],
    });
    expect(
      () => toUpdateComponents(args),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('content'),
        ),
      ),
    );
  });

  test('missing components throws', () {
    expect(
      () => toUpdateComponents(jsonEncode({'nope': 1})),
      throwsA(isA<FormatException>()),
    );
  });

  test('empty components throws', () {
    expect(
      () => toUpdateComponents(jsonEncode({'components': <Object>[]})),
      throwsA(isA<FormatException>()),
    );
  });

  test('non-JSON garbage in components throws a clear error', () {
    expect(
      () => toUpdateComponents(jsonEncode({'components': 'not json at all'})),
      throwsA(isA<FormatException>()),
    );
  });

  test('a "content" that is not a box throws', () {
    final args = jsonEncode({
      'components': [
        {'id': 'content', 'component': 'text', 'content': 'stray'},
      ],
    });
    expect(
      () => toUpdateComponents(args),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('box'),
        ),
      ),
    );
  });

  test("a 'content' referenced as another component's child throws", () {
    // A model that buries the real top under another box, with a stray
    // 'content' leaf, would otherwise silently lose its intended tree.
    final args = jsonEncode({
      'components': [
        {
          'id': 'top',
          'component': 'box',
          'title': 'top',
          'children': ['content'],
        },
        {'id': 'content', 'component': 'box', 'title': 'buried'},
      ],
    });
    expect(
      () => toUpdateComponents(args),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('top-level'),
        ),
      ),
    );
  });

  test('a model-supplied reserved id "root" throws with clear feedback', () {
    final args = jsonEncode({
      'components': [
        {'id': 'root', 'component': 'box', 'title': 'mine'},
      ],
    });
    expect(
      () => toUpdateComponents(args),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('reserved'),
        ),
      ),
    );
  });

  test(
    'coercedIntProps covers every integer leaf prop in the catalog',
    () async {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:genesis_console/console.g.json'),
      );
      final schema =
          jsonDecode(await File.fromUri(uri!).readAsString())
              as Map<String, Object?>;
      final items =
          ((((schema['properties'] as Map)['updateComponents']
                          as Map)['properties']
                      as Map)['components']
                  as Map)['items']
              as Map<String, Object?>;
      final variants = (items['oneOf'] as List).cast<Map<String, Object?>>();
      final intProps = <String>{};
      for (final variant in variants) {
        (variant['properties'] as Map).forEach((name, spec) {
          if (spec is Map && spec['type'] == 'integer') {
            intProps.add(name as String);
          }
        });
      }
      expect(
        intProps,
        isNotEmpty,
        reason: 'sanity: catalog has an integer prop',
      );
      expect(
        coercedIntProps.containsAll(intProps),
        isTrue,
        reason:
            'coerce.dart must coerce every catalog integer prop; missing: '
            '${intProps.difference(coercedIntProps)}',
      );
    },
  );
}
