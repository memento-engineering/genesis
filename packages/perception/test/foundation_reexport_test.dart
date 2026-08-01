import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

final class _Description with Diagnosticable {}

void main() {
  test(
    'perception re-exports the complete foundation surface through tree',
    () {
      const property = DiagnosticsProperty.string(
        name: 'label',
        level: DiagnosticsLevel.info,
        value: 'root',
      );
      final snapshot = TreeSnapshot(
        contractVersion: 1,
        projectedAt: DateTime.utc(2026, 8, 1),
        root: const TreeNode(
          seedType: 'Node',
          id: 'root',
          properties: [property],
          children: [],
        ),
      );
      expect(snapshot.root.properties.single, property);
      expect(_Description().toStringDeep(), '_Description\n');
    },
  );
}
