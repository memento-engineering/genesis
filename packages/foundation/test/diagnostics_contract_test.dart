import 'dart:convert';
import 'dart:io';

import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:test/test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 7, 23, 12, 29, 59);
  final properties = <DiagnosticsProperty>[
    const DiagnosticsProperty.string(
      name: 'label',
      level: DiagnosticsLevel.info,
      value: 'build',
    ),
    const DiagnosticsProperty.int(
      name: 'attempt',
      level: DiagnosticsLevel.fine,
      value: 2,
    ),
    const DiagnosticsProperty.double(
      name: 'cost',
      level: DiagnosticsLevel.info,
      value: 1.25,
    ),
    const DiagnosticsProperty.flag(
      name: 'failed',
      level: DiagnosticsLevel.warning,
      value: false,
    ),
    const DiagnosticsProperty.enumValue(
      name: 'state',
      level: DiagnosticsLevel.info,
      value: 'running',
      enumType: 'StepState',
    ),
    const DiagnosticsProperty.duration(
      name: 'elapsed',
      level: DiagnosticsLevel.fine,
      value: Duration(seconds: 3),
    ),
    DiagnosticsProperty.timestamp(
      name: 'startedAt',
      level: DiagnosticsLevel.info,
      value: timestamp,
    ),
    const DiagnosticsProperty.reference(
      name: 'work',
      level: DiagnosticsLevel.info,
      referenceKind: ReferenceKind.bead,
      value: 'work-1',
    ),
    const DiagnosticsProperty.object(
      name: 'allocation',
      level: DiagnosticsLevel.warning,
      properties: [
        DiagnosticsProperty.reference(
          name: 'process',
          level: DiagnosticsLevel.info,
          referenceKind: ReferenceKind.pid,
          value: '4242',
        ),
      ],
    ),
  ];

  test('version-1 snapshot round-trips the recursive tree', () {
    final snapshot = TreeSnapshot(
      contractVersion: 1,
      projectedAt: DateTime.utc(2026, 7, 23, 12, 30),
      root: TreeNode(
        seedType: 'Station',
        id: 'root-1',
        properties: properties,
        children: const [
          TreeNode(
            seedType: 'CircuitStep',
            id: 'step-1',
            key: 'specify',
            properties: [],
            children: [],
          ),
        ],
      ),
    );
    final json = snapshot.toJson();
    expect(json['contractVersion'], 1);
    expect(json['projectedAt'], '2026-07-23T12:30:00.000Z');
    expect(TreeSnapshot.fromJson(json), snapshot);
  });

  test('all nine property kinds round-trip with exhaustive consumption', () {
    final kinds = <String>[];
    for (final property in properties) {
      kinds.add(switch (property) {
        DiagnosticsStringProperty() => 'string',
        DiagnosticsIntProperty() => 'int',
        DiagnosticsDoubleProperty() => 'double',
        DiagnosticsFlagProperty() => 'flag',
        DiagnosticsEnumProperty() => 'enumValue',
        DiagnosticsDurationProperty() => 'duration',
        DiagnosticsTimestampProperty() => 'timestamp',
        DiagnosticsReferenceProperty() => 'reference',
        DiagnosticsObjectProperty() => 'object',
      });
      expect(DiagnosticsProperty.fromJson(property.toJson()), property);
    }
    expect(kinds, [
      'string',
      'int',
      'double',
      'flag',
      'enumValue',
      'duration',
      'timestamp',
      'reference',
      'object',
    ]);
  });

  test('nested references retain their typed value', () {
    expect(
      DiagnosticsProperty.fromJson(properties.last.toJson()),
      properties.last,
    );
  });

  test('copyWith and value equality preserve the deployed immutable API', () {
    final original = TreeNode(
      seedType: 'Station',
      id: 'root',
      properties: properties,
      children: const [],
    );
    expect(original.copyWith(), original);
    expect(original.copyWith(key: 'diagnostics').key, 'diagnostics');
    expect(original.copyWith(key: null).key, isNull);

    final property = properties.first as DiagnosticsStringProperty;
    expect(property.copyWith(), property);
    expect(property.copyWith(value: 'deploy').value, 'deploy');
  });

  test('duration and timestamps retain version-1 encodings', () {
    expect(
      const DiagnosticsProperty.duration(
        name: 'elapsed',
        level: DiagnosticsLevel.fine,
        value: Duration(microseconds: 42),
      ).toJson()['value'],
      42,
    );
    expect(
      DiagnosticsProperty.timestamp(
        name: 'startedAt',
        level: DiagnosticsLevel.info,
        value: DateTime.parse('2026-07-23T07:29:59-05:00'),
      ).toJson()['value'],
      '2026-07-23T12:29:59.000Z',
    );
  });

  test('malformed values and enum names fail loudly', () {
    expect(
      () => DiagnosticsProperty.fromJson(const {
        'kind': 'int',
        'name': 'attempt',
        'level': 'info',
        'value': 'two',
      }),
      throwsA(isA<CheckedFromJsonException>()),
    );
    expect(
      () => DiagnosticsProperty.fromJson(const {
        'kind': 'reference',
        'name': 'work',
        'level': 'info',
        'referenceKind': 'stationLock',
        'value': 'x',
      }),
      throwsA(isA<CheckedFromJsonException>()),
    );
  });

  test('unknown property kind fails loudly', () {
    expect(
      () => DiagnosticsProperty.fromJson(const {
        'kind': 'treeDelta',
        'name': 'reserved',
        'level': 'info',
        'value': 'x',
      }),
      throwsA(isA<CheckedFromJsonException>()),
    );
  });

  test('the existing grid replay version-1 shape deserializes', () {
    final json =
        jsonDecode(
              File(
                'test/fixtures/grid_replay_snapshot_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final snapshot = TreeSnapshot.fromJson(json);
    expect(snapshot.contractVersion, 1);
    expect(snapshot.root.seedType, 'Grid');
    expect(snapshot.root.children.single.seedType, 'Substation');
    final encoded = jsonEncode(snapshot.toJson());
    expect(encoded, contains('"referenceKind":"substation"'));
    expect(encoded, contains('"referenceKind":"bead"'));
    expect(encoded, contains('"referenceKind":"session"'));
  });
}
