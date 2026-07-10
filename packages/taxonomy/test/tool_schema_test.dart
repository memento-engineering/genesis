import 'dart:convert';
import 'dart:io';

import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:test/test.dart';

void main() {
  final schemaMap =
      (jsonDecode(File('test/src/fixture.g.json').readAsStringSync()) as Map)
          .cast<String, Object?>();

  Map<String, Object?> variant(String typeName) {
    final updateComponents =
        ((schemaMap['properties'] as Map)['updateComponents'] as Map)
            .cast<String, Object?>();
    final components =
        ((updateComponents['properties'] as Map)['components'] as Map)
            .cast<String, Object?>();
    final oneOf = ((components['items'] as Map)['oneOf'] as List)
        .cast<Map<Object?, Object?>>();
    return oneOf
        .map((v) => v.cast<String, Object?>())
        .firstWhere(
          (v) =>
              ((v['properties'] as Map)['component'] as Map)['const'] ==
              typeName,
        );
  }

  Map<String, Object?> propsOf(Map<String, Object?> v) =>
      (v['properties'] as Map).cast<String, Object?>();

  group('tool-schema content', () {
    test('prop types, descriptions, and defaults flow through', () {
      final gauge = propsOf(variant('gauge'));
      expect((gauge['label'] as Map)['type'], 'string');
      expect((gauge['value'] as Map)['type'], 'number');
      expect((gauge['value'] as Map)['description'], 'Current reading.');
      expect((gauge['scale'] as Map)['type'], 'integer');
      expect((gauge['scale'] as Map)['default'], 10);
      expect((gauge['enabled'] as Map)['type'], 'boolean');
      expect((gauge['enabled'] as Map)['default'], true);
      expect((gauge['align'] as Map)['type'], 'string');
      expect((gauge['align'] as Map)['enum'], ['start', 'center', 'end']);
      expect((gauge['align'] as Map)['default'], 'start');
      // Required props carry no default keyword.
      expect(gauge['value'] as Map, isNot(contains('default')));
    });

    test('required lists id, component, and only the required props', () {
      expect(variant('gauge')['required'], [
        'id',
        'component',
        'label',
        'value',
      ]);
      expect(variant('label')['required'], [
        'id',
        'component',
        'name',
        'value',
      ]);
      expect(variant('panel')['required'], ['id', 'component', 'name']);
    });

    test('children only on containers; leaves close their shape', () {
      expect(propsOf(variant('panel')), contains('children'));
      expect(propsOf(variant('label')), isNot(contains('children')));
      expect(propsOf(variant('gauge')), isNot(contains('children')));
      expect(variant('gauge')['additionalProperties'], false);
      expect(variant('panel')['additionalProperties'], false);
    });

    test('action declarations surface as x-actions and as prose', () {
      final gauge = variant('gauge');
      final actions = (gauge['x-actions'] as Map).cast<String, Object?>();
      expect(actions.keys, ['reset', 'set']);
      expect((actions['set'] as Map)['description'], contains('context.value'));
      expect(
        gauge['description'],
        allOf(
          contains('AFFORDS CLIENT ACTIONS'),
          contains('sourceComponentId'),
          contains('"set"'),
          contains('"reset"'),
        ),
      );
      expect(variant('label'), isNot(contains('x-actions')));
      expect(variant('panel'), isNot(contains('x-actions')));
    });
  });

  group('validator-executed conformance (draft 2020-12)', () {
    // The oracle is the genui ecosystem's own draft-2020-12 validator
    // (json_schema_builder, the lib a2ui_core + genai_primitives build on):
    // if it accepts our hand-emitted schema and the documents below, an A2UI
    // client built on the same stack agrees. validate() is async and returns
    // the list of errors — empty means valid.
    final schema = Schema.fromMap(schemaMap);

    Future<List<ValidationError>> errorsFor(Object? doc) =>
        schema.validate(doc);

    Map<String, Object?> message(List<Map<String, Object?>> components) => {
      'version': 'v0.9',
      'updateComponents': {'surfaceId': 'main', 'components': components},
    };

    const goodPanel = {
      'id': 'root',
      'component': 'panel',
      'name': 'dash',
      'children': ['l1', 'g1'],
    };
    const goodLabel = {
      'id': 'l1',
      'component': 'label',
      'name': 'Name',
      'value': 'Nico',
    };
    const goodGauge = {
      'id': 'g1',
      'component': 'gauge',
      'label': 'Fuel',
      'value': 3.5,
    };

    test('a known-good document validates', () async {
      final errors = await errorsFor(
        message([goodPanel, goodLabel, goodGauge]),
      );
      expect(errors, isEmpty, reason: '$errors');
    });

    test('optional props with defaults validate when present', () async {
      final errors = await errorsFor(
        message([
          {
            ...goodGauge,
            'id': 'root',
            'scale': 20,
            'enabled': false,
            'align': 'end',
          },
        ]),
      );
      expect(errors, isEmpty, reason: '$errors');
    });

    test('missing required prop fails validation', () async {
      final bad = {...goodLabel, 'id': 'root'}..remove('value');
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('children on a leaf fail validation', () async {
      final bad = {
        ...goodLabel,
        'id': 'root',
        'children': ['x'],
      };
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('unknown prop fails validation', () async {
      final bad = {...goodGauge, 'id': 'root', 'color': 'red'};
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('wrong prop type fails validation', () async {
      final bad = {...goodGauge, 'id': 'root', 'value': 'high'};
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('non-integer where integer required fails validation', () async {
      final bad = {...goodGauge, 'id': 'root', 'scale': 2.5};
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('enum value outside the declared set fails validation', () async {
      final bad = {...goodGauge, 'id': 'root', 'align': 'left'};
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('unknown component type fails validation', () async {
      final bad = {'id': 'root', 'component': 'toggle'};
      expect(await errorsFor(message([bad])), isNotEmpty);
    });

    test('wrong envelope version fails validation', () async {
      final bad = {
        'version': 'v0.8',
        'updateComponents': {
          'surfaceId': 'main',
          'components': [
            {...goodGauge, 'id': 'root'},
          ],
        },
      };
      expect(await errorsFor(bad), isNotEmpty);
    });
  });
}
