import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

import 'src/fixture.g.dart';
import 'src/fixture_seeds.dart';

void main() {
  group('registry round-trip', () {
    test('registry carries catalog provenance and types', () {
      expect(componentRegistry.catalogName, 'fixture');
      expect(componentRegistry.catalogVersion, '0.1.0');
      expect(componentRegistry.typeNames, ['gauge', 'label', 'panel']);
    });

    test('every prop kind constructs (string/number/integer/boolean/enum)', () {
      final seed =
          componentRegistry.buildComponent(
                'gauge',
                {
                  'label': 'Fuel',
                  'value': 7.5,
                  'scale': 20,
                  'enabled': false,
                  'align': 'center',
                },
                const [],
                'g1',
              )
              as Gauge;
      expect(seed.label, 'Fuel');
      expect(seed.value, 7.5);
      expect(seed.scale, 20);
      expect(seed.enabled, isFalse);
      expect(seed.align, 'center');
      expect(seed.key, 'g1');
    });

    test('omitted optional props take their catalog defaults', () {
      final seed =
          componentRegistry.buildComponent(
                'gauge',
                {'label': 'Fuel', 'value': 1.0},
                const [],
                'g1',
              )
              as Gauge;
      expect(seed.scale, 10);
      expect(seed.enabled, isTrue);
      expect(seed.align, 'start');
    });

    test('explicit null on an optional prop takes the default', () {
      final seed =
          componentRegistry.buildComponent(
                'gauge',
                {'label': 'Fuel', 'value': 1.0, 'align': null},
                const [],
                'g1',
              )
              as Gauge;
      expect(seed.align, 'start');
    });

    test('integral JSON numbers widen to double for number props', () {
      final seed =
          componentRegistry.buildComponent(
                'gauge',
                {'label': 'Fuel', 'value': 7},
                const [],
                'g1',
              )
              as Gauge;
      expect(seed.value, 7.0);
    });

    test('containers receive children; named string props bind', () {
      final label =
          componentRegistry.buildComponent(
                'label',
                {'name': 'Name', 'value': 'Nico'},
                const [],
                'l1',
              )
              as Label;
      expect(label.name, 'Name');
      expect(label.value, 'Nico');

      final panel =
          componentRegistry.buildComponent(
                'panel',
                {'name': 'form'},
                [label],
                'root',
              )
              as Panel;
      expect(panel.name, 'form');
      expect(panel.children, [label]);
      expect(panel.key, 'root');
    });
  });

  group('structured construction errors (the LLM feedback channel)', () {
    test('unknown component type', () {
      expect(
        () => componentRegistry.buildComponent(
          'toggle',
          const {},
          const [],
          null,
        ),
        throwsA(
          isA<UnknownComponentTypeException>()
              .having((e) => e.componentType, 'componentType', 'toggle')
              .having((e) => e.knownTypes, 'knownTypes', [
                'gauge',
                'label',
                'panel',
              ])
              .having(
                (e) => e.message,
                'message',
                contains('unknown component type "toggle"'),
              ),
        ),
      );
    });

    test('missing required prop', () {
      expect(
        () => componentRegistry.buildComponent(
          'gauge',
          {'label': 'Fuel'},
          const [],
          null,
        ),
        throwsA(
          isA<MissingRequiredPropException>()
              .having((e) => e.componentType, 'componentType', 'gauge')
              .having((e) => e.prop, 'prop', 'value')
              .having((e) => e.expectedType, 'expectedType', 'number'),
        ),
      );
    });

    test('explicit null on a required prop is missing', () {
      expect(
        () => componentRegistry.buildComponent(
          'gauge',
          {'label': 'Fuel', 'value': null},
          const [],
          null,
        ),
        throwsA(isA<MissingRequiredPropException>()),
      );
    });

    test('wrong prop types, per kind', () {
      void expectMismatch(
        Map<String, Object?> props,
        String prop,
        String expectedType,
      ) {
        expect(
          () => componentRegistry.buildComponent(
            'gauge',
            {'label': 'Fuel', 'value': 1.0, ...props},
            const [],
            null,
          ),
          throwsA(
            isA<PropTypeMismatchException>()
                .having((e) => e.componentType, 'componentType', 'gauge')
                .having((e) => e.prop, 'prop', prop)
                .having((e) => e.expectedType, 'expectedType', expectedType),
          ),
        );
      }

      expectMismatch({'label': 42}, 'label', 'string');
      expectMismatch({'value': 'high'}, 'value', 'number');
      expectMismatch({'scale': 2.5}, 'scale', 'integer');
      expectMismatch({'enabled': 'yes'}, 'enabled', 'boolean');
      expectMismatch({'align': 5}, 'align', 'enum (string)');
    });

    test('enum value outside the declared set', () {
      expect(
        () => componentRegistry.buildComponent(
          'gauge',
          {'label': 'Fuel', 'value': 1.0, 'align': 'left'},
          const [],
          null,
        ),
        throwsA(
          isA<InvalidEnumValueException>()
              .having((e) => e.componentType, 'componentType', 'gauge')
              .having((e) => e.prop, 'prop', 'align')
              .having((e) => e.allowedValues, 'allowedValues', [
                'start',
                'center',
                'end',
              ])
              .having((e) => e.actualValue, 'actualValue', 'left')
              .having((e) => e.message, 'message', contains('"start"')),
        ),
      );
    });

    test('unknown prop', () {
      expect(
        () => componentRegistry.buildComponent(
          'label',
          {'name': 'n', 'value': 'v', 'color': 'red'},
          const [],
          null,
        ),
        throwsA(
          isA<UnknownPropException>()
              .having((e) => e.componentType, 'componentType', 'label')
              .having((e) => e.prop, 'prop', 'color')
              .having((e) => e.knownProps, 'knownProps', ['name', 'value']),
        ),
      );
    });

    test('children on a leaf', () {
      final child = componentRegistry.buildComponent(
        'label',
        {'name': 'n', 'value': 'v'},
        const [],
        'l1',
      );
      expect(
        () => componentRegistry.buildComponent(
          'gauge',
          {'label': 'Fuel', 'value': 1.0},
          [child],
          null,
        ),
        throwsA(
          isA<ChildrenOnLeafException>()
              .having((e) => e.componentType, 'componentType', 'gauge')
              .having((e) => e.childCount, 'childCount', 1),
        ),
      );
    });

    test('errors are TaxonomyExceptions, switchable by family', () {
      try {
        componentRegistry.buildComponent('toggle', const {}, const [], null);
        fail('expected a throw');
      } on TaxonomyException catch (e) {
        final family = switch (e) {
          CatalogException() => 'catalog',
          ComponentBuildException() => 'build',
          TreeShapeException() => 'shape',
        };
        expect(family, 'build');
      }
    });
  });
}
