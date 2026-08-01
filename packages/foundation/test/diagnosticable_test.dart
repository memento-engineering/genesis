import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:test/test.dart';

enum _Example { ready }

final class _Empty with Diagnosticable {}

final class _Leaf with Diagnosticable {
  _Leaf(this.label);

  final String label;

  @override
  void debugFillProperties(List<DiagnosticsProperty> properties) {
    properties.add(
      DiagnosticsProperty.string(
        name: 'label',
        level: DiagnosticsLevel.info,
        value: label,
      ),
    );
  }
}

final class _AllProperties with Diagnosticable {
  @override
  void debugFillProperties(List<DiagnosticsProperty> properties) {
    properties.addAll([
      const DiagnosticsProperty.string(
        name: 'string',
        level: DiagnosticsLevel.fine,
        value: 'text',
      ),
      const DiagnosticsProperty.int(
        name: 'int',
        level: DiagnosticsLevel.info,
        value: 42,
      ),
      const DiagnosticsProperty.double(
        name: 'double',
        level: DiagnosticsLevel.warning,
        value: 2.5,
      ),
      const DiagnosticsProperty.flag(
        name: 'flag',
        level: DiagnosticsLevel.error,
        value: true,
      ),
      DiagnosticsProperty.enumValue(
        name: 'enum',
        level: DiagnosticsLevel.info,
        enumType: '_Example',
        value: _Example.ready.name,
      ),
      const DiagnosticsProperty.duration(
        name: 'duration',
        level: DiagnosticsLevel.fine,
        value: Duration(seconds: 3),
      ),
      DiagnosticsProperty.timestamp(
        name: 'timestamp',
        level: DiagnosticsLevel.info,
        value: DateTime.parse('2026-08-01T01:02:03-05:00'),
      ),
      const DiagnosticsProperty.reference(
        name: 'reference',
        level: DiagnosticsLevel.warning,
        referenceKind: ReferenceKind.bead,
        value: 'abc',
      ),
      const DiagnosticsProperty.object(
        name: 'object',
        level: DiagnosticsLevel.error,
        properties: [
          DiagnosticsProperty.string(
            name: 'nested',
            level: DiagnosticsLevel.info,
            value: 'value',
          ),
        ],
      ),
    ]);
  }
}

final class _Root with Diagnosticable, DiagnosticableTree {
  _Root(this.children);

  final List<Diagnosticable> children;

  @override
  List<Diagnosticable> debugDescribeChildren() => children;
}

void main() {
  test('default hooks render only the runtime type', () {
    expect(_Empty().toStringDeep(), '_Empty\n');
  });

  test('renders all diagnostics property variants deterministically', () {
    expect(
      _AllProperties().toStringDeep(),
      '_AllProperties\n'
      '  string: text (fine)\n'
      '  int: 42 (info)\n'
      '  double: 2.5 (warning)\n'
      '  flag: true (error)\n'
      '  enum: _Example.ready (info)\n'
      '  duration: 0:00:03.000000 (fine)\n'
      '  timestamp: 2026-08-01T06:02:03.000Z (info)\n'
      '  reference: bead:abc (warning)\n'
      '  object: {nested: value} (error)\n',
    );
  });

  test('renders ordered children with recursive two-space indentation', () {
    final root = _Root([
      _Leaf('first'),
      _Root([_Leaf('nested')]),
    ]);
    expect(
      root.toStringDeep(),
      '_Root\n'
      '  _Leaf\n'
      '    label: first (info)\n'
      '  _Root\n'
      '    _Leaf\n'
      '      label: nested (info)\n',
    );
  });
}
