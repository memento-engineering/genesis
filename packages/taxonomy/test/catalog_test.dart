import 'dart:convert';
import 'dart:io';

import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

/// Fake plugin (Fakes-not-mocks) claiming an arbitrary key set.
final class FakePlugin extends CatalogPlugin {
  const FakePlugin(this.name, this.typeKeys);

  @override
  final String name;

  @override
  final Set<String> typeKeys;

  @override
  Object parseTypeValue({
    required String typeName,
    required String key,
    required Object? value,
  }) => value ?? 'parsed';
}

/// Minimal valid leaf type spec, overridable per test.
Map<String, Object?> leafType({
  Map<String, Object?>? props,
  Map<String, Object?>? dart,
  Map<String, Object?> extra = const {},
  bool container = false,
}) => {
  'description': 'A leaf.',
  'container': container,
  'props': props ?? const {},
  'dart':
      dart ??
      {
        'class': 'Label',
        'import': 'fixture_seeds.dart',
        'positionalProps': const <String>[],
        'namedProps': const <String>[],
      },
  ...extra,
};

/// Minimal valid catalog document, overridable per test.
String catalogJson({
  Map<String, Object?>? provenance,
  Map<String, Object?>? types,
}) => jsonEncode({
  'catalog': provenance ?? {'name': 'test', 'version': '0.0.1'},
  'types': types ?? {'leaf': leafType()},
});

void main() {
  group('Catalog.parse happy path (fixture catalog)', () {
    late Catalog catalog;

    setUpAll(() {
      catalog = Catalog.parse(
        File('test/src/fixture.catalog.json').readAsStringSync(),
      );
    });

    test('provenance block parses', () {
      expect(catalog.name, 'fixture');
      expect(catalog.version, '0.1.0');
      expect(catalog.description, contains('genesis_tree Seeds'));
    });

    test('types are sorted by name', () {
      expect(catalog.types.map((t) => t.name), ['gauge', 'label', 'panel']);
    });

    test('container/leaf flags parse', () {
      expect(catalog.typeNamed('panel')!.container, isTrue);
      expect(catalog.typeNamed('label')!.container, isFalse);
      expect(catalog.typeNamed('gauge')!.container, isFalse);
    });

    test('typed props parse in catalog order with kinds and defaults', () {
      final gauge = catalog.typeNamed('gauge')!;
      expect(gauge.props.map((p) => p.name), [
        'label',
        'value',
        'scale',
        'enabled',
        'align',
      ]);

      final label = gauge.propNamed('label')!;
      expect(label.type, PropType.string);
      expect(label.required, isTrue);
      expect(label.defaultValue, isNull);

      final value = gauge.propNamed('value')!;
      expect(value.type, PropType.number);
      expect(value.required, isTrue);

      final scale = gauge.propNamed('scale')!;
      expect(scale.type, PropType.integer);
      expect(scale.required, isFalse);
      expect(scale.defaultValue, 10);

      final enabled = gauge.propNamed('enabled')!;
      expect(enabled.type, PropType.boolean);
      expect(enabled.defaultValue, true);

      final align = gauge.propNamed('align')!;
      expect(align.type, PropType.enumeration);
      expect(align.enumValues, ['start', 'center', 'end']);
      expect(align.defaultValue, 'start');
    });

    test('dart bindings parse', () {
      final panel = catalog.typeNamed('panel')!.dart;
      expect(panel.className, 'Panel');
      expect(panel.import, 'fixture_seeds.dart');
      expect(panel.positionalProps, ['name']);
      expect(panel.childrenParam, 'children');

      final gauge = catalog.typeNamed('gauge')!.dart;
      expect(gauge.childrenParam, isNull);
      expect(gauge.namedProps, ['value', 'scale', 'enabled', 'align']);
    });

    test('action declarations ride the plugin seam into typed data', () {
      final actions = catalog.typeNamed('gauge')!.actions;
      expect(actions.keys, ['reset', 'set']); // sorted by the plugin
      expect(actions['set']!.description, contains('context.value'));
      expect(catalog.typeNamed('label')!.actions, isEmpty);
      expect(catalog.typeNamed('panel')!.actions, isEmpty);
    });
  });

  group('structured catalog format errors', () {
    test('unparseable JSON', () {
      expect(
        () => Catalog.parse('not json'),
        throwsA(
          isA<CatalogFormatException>().having((e) => e.path, 'path', ''),
        ),
      );
    });

    test('missing provenance block', () {
      expect(
        () => Catalog.parse(jsonEncode({'types': <String, Object?>{}})),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'catalog',
          ),
        ),
      );
    });

    test('unknown top-level key', () {
      expect(
        () => Catalog.parse(
          jsonEncode({
            'catalog': {'name': 't', 'version': '1'},
            'types': {'leaf': leafType()},
            'extras': true,
          }),
        ),
        throwsA(
          isA<CatalogFormatException>().having((e) => e.path, 'path', 'extras'),
        ),
      );
    });

    test('empty types map', () {
      expect(
        () => Catalog.parse(catalogJson(types: {})),
        throwsA(
          isA<CatalogFormatException>().having((e) => e.path, 'path', 'types'),
        ),
      );
    });

    test('unknown prop type name', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {'type': 'float', 'required': true, 'description': 'd'},
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>()
              .having((e) => e.path, 'path', 'types/leaf/props/p/type')
              .having((e) => e.actual, 'actual', 'float'),
        ),
      );
    });

    test('optional prop without default is rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'string',
                    'required': false,
                    'description': 'd',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/default',
          ),
        ),
      );
    });

    test('required prop with default is rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'string',
                    'required': true,
                    'default': 'x',
                    'description': 'd',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/default',
          ),
        ),
      );
    });

    test('default type must match the prop type', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'integer',
                    'required': false,
                    'default': 'ten',
                    'description': 'd',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>()
              .having((e) => e.path, 'path', 'types/leaf/props/p/default')
              .having((e) => e.actual, 'actual', 'ten'),
        ),
      );
    });

    test('enum requires non-empty string values', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {'type': 'enum', 'required': true, 'description': 'd'},
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/values',
          ),
        ),
      );
    });

    test('enum default must be a declared value', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'enum',
                    'values': ['a', 'b'],
                    'required': false,
                    'default': 'c',
                    'description': 'd',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/default',
          ),
        ),
      );
    });

    test('values on a non-enum prop is rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'string',
                    'values': ['a'],
                    'required': true,
                    'description': 'd',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/values',
          ),
        ),
      );
    });

    test('dart binding must cover exactly the declared props', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {'type': 'string', 'required': true, 'description': 'd'},
                },
                // Binding omits 'p'.
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/dart',
          ),
        ),
      );
    });

    test('container without childrenParam is rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(types: {'box': leafType(container: true)}),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/box/dart/childrenParam',
          ),
        ),
      );
    });

    test('leaf with childrenParam is rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': const <String>[],
                  'namedProps': const <String>[],
                  'childrenParam': 'children',
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/dart/childrenParam',
          ),
        ),
      );
    });

    test('unknown prop-level key is rejected (props are core vocabulary)', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                props: {
                  'p': {
                    'type': 'string',
                    'required': true,
                    'description': 'd',
                    'units': 'em',
                  },
                },
                dart: {
                  'class': 'L',
                  'import': 'l.dart',
                  'positionalProps': ['p'],
                  'namedProps': const <String>[],
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/props/p/units',
          ),
        ),
      );
    });
  });

  group('loud plugin keys (seam 1)', () {
    test('unhandled type-level key fails loudly, listing every key', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'a': leafType(extra: {'affordances': true, 'zeta': 1}),
              'b': leafType(extra: {'affordances': true}),
            },
          ),
        ),
        throwsA(
          isA<UnhandledCatalogKeysException>()
              .having((e) => e.unhandledKeysByType, 'unhandledKeysByType', {
                'a': ['affordances', 'zeta'],
                'b': ['affordances'],
              })
              .having((e) => e.registeredPlugins, 'registeredPlugins', [
                'actions',
              ])
              .having(
                (e) => e.message,
                'message',
                allOf(contains('"affordances"'), contains('"zeta"')),
              ),
        ),
      );
    });

    test('even the shipped actions block is plugin vocabulary', () {
      final json = catalogJson(
        types: {
          'leaf': leafType(
            extra: {
              'actions': {
                'poke': {'description': 'Poke it.'},
              },
            },
          ),
        },
      );
      // With no plugins registered, the actions key itself is unhandled.
      expect(
        () => Catalog.parse(json, plugins: const []),
        throwsA(
          isA<UnhandledCatalogKeysException>().having(
            (e) => e.unhandledKeysByType,
            'unhandledKeysByType',
            {
              'leaf': ['actions'],
            },
          ),
        ),
      );
      // With the default plugin set it parses into typed declarations.
      final catalog = Catalog.parse(json);
      expect(
        catalog.typeNamed('leaf')!.actions['poke']!.description,
        'Poke it.',
      );
    });

    test('a registered fake plugin claims a custom key', () {
      final catalog = Catalog.parse(
        catalogJson(
          types: {
            'leaf': leafType(extra: {'aura': 'blue'}),
          },
        ),
        plugins: const [
          FakePlugin('aura', {'aura'}),
        ],
      );
      expect(catalog.typeNamed('leaf')!.extensions['aura'], 'blue');
    });

    test('two plugins claiming one key is a configuration error', () {
      expect(
        () => Catalog.parse(
          catalogJson(),
          plugins: const [
            FakePlugin('one', {'aura'}),
            FakePlugin('two', {'aura'}),
          ],
        ),
        throwsA(
          isA<CatalogFormatException>()
              .having((e) => e.path, 'path', 'plugins')
              .having((e) => e.actual.toString(), 'actual', contains('"aura"')),
        ),
      );
    });

    test('a plugin claiming a core key is a configuration error', () {
      expect(
        () => Catalog.parse(
          catalogJson(),
          plugins: const [
            FakePlugin('bad', {'props'}),
          ],
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'plugins',
          ),
        ),
      );
    });
  });

  group('ActionsCatalogPlugin input validation', () {
    test('actions must be a non-empty map', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(extra: {'actions': <String, Object?>{}}),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/actions',
          ),
        ),
      );
    });

    test('an action needs a non-empty description', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                extra: {
                  'actions': {'poke': <String, Object?>{}},
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/actions/poke/description',
          ),
        ),
      );
    });

    test('unknown keys inside an action spec are rejected', () {
      expect(
        () => Catalog.parse(
          catalogJson(
            types: {
              'leaf': leafType(
                extra: {
                  'actions': {
                    'poke': {'description': 'd', 'payload': 'x'},
                  },
                },
              ),
            },
          ),
        ),
        throwsA(
          isA<CatalogFormatException>().having(
            (e) => e.path,
            'path',
            'types/leaf/actions/poke/payload',
          ),
        ),
      );
    });
  });
}
