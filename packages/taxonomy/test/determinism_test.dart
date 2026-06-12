import 'dart:convert';
import 'dart:io';

import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

void main() {
  final catalogJson = File('test/src/fixture.catalog.json').readAsStringSync();

  group('determinism (ADR-0002 Decision 1)', () {
    test('two generator runs are byte-identical', () {
      final first = generateFromCatalog(catalogJson);
      final second = generateFromCatalog(catalogJson);
      expect(second.registryDart, first.registryDart);
      expect(second.toolSchemaJson, first.toolSchemaJson);
    });

    test('output is independent of catalog key order', () {
      // Re-encode the catalog with the types map reversed; the emitters sort
      // types by name, so the projections must not change.
      final decoded = (jsonDecode(catalogJson) as Map).cast<String, Object?>();
      final types = (decoded['types'] as Map).cast<String, Object?>();
      final reversed = {
        ...decoded,
        'types': {
          for (final name in types.keys.toList().reversed) name: types[name],
        },
      };
      final fromOriginal = generateFromCatalog(catalogJson);
      final fromReversed = generateFromCatalog(jsonEncode(reversed));
      expect(fromReversed.registryDart, fromOriginal.registryDart);
      expect(fromReversed.toolSchemaJson, fromOriginal.toolSchemaJson);
    });
  });

  group('generator-in-sync (the standing guard on committed artifacts)', () {
    test('committed fixture.g.dart matches in-memory regeneration', () {
      final onDisk = File('test/src/fixture.g.dart').readAsStringSync();
      final inMemory = generateFromCatalog(catalogJson).registryDart;
      expect(
        onDisk,
        inMemory,
        reason:
            'test/src/fixture.g.dart is OUT OF SYNC with '
            'fixture.catalog.json — re-run: dart run build_runner build',
      );
    });

    test('committed fixture.g.json matches in-memory regeneration', () {
      final onDisk = File('test/src/fixture.g.json').readAsStringSync();
      final inMemory = generateFromCatalog(catalogJson).toolSchemaJson;
      expect(
        onDisk,
        inMemory,
        reason:
            'test/src/fixture.g.json is OUT OF SYNC with '
            'fixture.catalog.json — re-run: dart run build_runner build',
      );
    });
  });

  group('provenance headers (seam 2)', () {
    // A second catalog with a different name block: headers must follow the
    // catalog, never a hardcoded package or catalog name (the spike-5
    // complaint).
    final otherCatalog = jsonEncode({
      'catalog': {'name': 'elsewhere', 'version': '9.9.9'},
      'types': {
        'tag': {
          'description': 'A bare tag.',
          'container': false,
          'props': {
            'name': {
              'type': 'string',
              'required': true,
              'description': 'Tag text.',
            },
          },
          'dart': {
            'class': 'Tag',
            'import': 'package:elsewhere/elsewhere.dart',
            'positionalProps': ['name'],
            'namedProps': <String>[],
          },
        },
      },
    });

    test('registry header names the catalog from its name block', () {
      final registry = generateFromCatalog(otherCatalog).registryDart;
      expect(registry, startsWith('// GENERATED — do not edit.'));
      expect(registry, contains("from catalog 'elsewhere' v9.9.9"));
      expect(registry, contains("catalogName: 'elsewhere'"));
      expect(registry, contains("catalogVersion: '9.9.9'"));
      expect(registry, isNot(contains('fixture')));
    });

    test('tool schema provenance names the catalog from its name block', () {
      final schema =
          (jsonDecode(generateFromCatalog(otherCatalog).toolSchemaJson) as Map)
              .cast<String, Object?>();
      expect(schema[r'$comment'], contains('GENERATED — do not edit.'));
      expect(schema[r'$comment'], contains("from catalog 'elsewhere' v9.9.9"));
      expect(schema['title'], 'updateComponents (elsewhere catalog v9.9.9)');
      expect(schema['description'], contains('the elsewhere catalog'));
    });
  });
}
