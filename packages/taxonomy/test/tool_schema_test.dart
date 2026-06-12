import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
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
    final schema = JsonSchema.create(
      schemaMap,
      schemaVersion: SchemaVersion.draft2020_12,
    );

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

    test('a known-good document validates', () {
      final results = schema.validate(
        message([goodPanel, goodLabel, goodGauge]),
      );
      expect(results.isValid, isTrue, reason: '${results.errors}');
    });

    test('optional props with defaults validate when present', () {
      final results = schema.validate(
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
      expect(results.isValid, isTrue, reason: '${results.errors}');
    });

    test('missing required prop fails validation', () {
      final bad = {...goodLabel, 'id': 'root'}..remove('value');
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('children on a leaf fail validation', () {
      final bad = {
        ...goodLabel,
        'id': 'root',
        'children': ['x'],
      };
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('unknown prop fails validation', () {
      final bad = {...goodGauge, 'id': 'root', 'color': 'red'};
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('wrong prop type fails validation', () {
      final bad = {...goodGauge, 'id': 'root', 'value': 'high'};
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('non-integer where integer required fails validation', () {
      final bad = {...goodGauge, 'id': 'root', 'scale': 2.5};
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('enum value outside the declared set fails validation', () {
      final bad = {...goodGauge, 'id': 'root', 'align': 'left'};
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('unknown component type fails validation', () {
      final bad = {'id': 'root', 'component': 'toggle'};
      expect(schema.validate(message([bad])).isValid, isFalse);
    });

    test('wrong envelope version fails validation', () {
      final bad = {
        'version': 'v0.8',
        'updateComponents': {
          'surfaceId': 'main',
          'components': [
            {...goodGauge, 'id': 'root'},
          ],
        },
      };
      expect(schema.validate(bad).isValid, isFalse);
    });
  });
}
