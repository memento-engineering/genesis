import 'dart:io';

import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

/// Standing guard on the committed test-catalog artifacts (A22 / ADR-0002
/// Decision 1, mirroring genesis_taxonomy / genesis_dialogue): the committed
/// consent_fixture.g.dart / .g.json must equal an in-memory regeneration from
/// the catalog. If this is red, re-run:
///   dart run build_runner build
void main() {
  final catalogJson = File(
    'test/src/consent_fixture.catalog.json',
  ).readAsStringSync();

  group('consent test-catalog generator-in-sync', () {
    test('two generator runs are byte-identical (determinism)', () {
      final first = generateFromCatalog(catalogJson);
      final second = generateFromCatalog(catalogJson);
      expect(second.registryDart, first.registryDart);
      expect(second.toolSchemaJson, first.toolSchemaJson);
    });

    test('committed consent_fixture.g.dart matches regeneration', () {
      final onDisk = File('test/src/consent_fixture.g.dart').readAsStringSync();
      final inMemory = generateFromCatalog(catalogJson).registryDart;
      expect(
        onDisk,
        inMemory,
        reason:
            'test/src/consent_fixture.g.dart is OUT OF SYNC with '
            'consent_fixture.catalog.json — re-run: dart run build_runner '
            'build',
      );
    });

    test('committed consent_fixture.g.json matches regeneration', () {
      final onDisk = File('test/src/consent_fixture.g.json').readAsStringSync();
      final inMemory = generateFromCatalog(catalogJson).toolSchemaJson;
      expect(
        onDisk,
        inMemory,
        reason:
            'test/src/consent_fixture.g.json is OUT OF SYNC with '
            'consent_fixture.catalog.json — re-run: dart run build_runner '
            'build',
      );
    });

    test('the catalog declares the press/set affordances on counter', () {
      final catalog = Catalog.parse(catalogJson);
      final counter = catalog.typeNamed('counter');
      expect(counter, isNotNull);
      expect(counter!.actions.keys.toList()..sort(), ['press', 'set']);
      // node/field afford nothing — the affordance gate must reject actions
      // against them.
      expect(catalog.typeNamed('node')!.actions, isEmpty);
      expect(catalog.typeNamed('field')!.actions, isEmpty);
    });
  });
}
