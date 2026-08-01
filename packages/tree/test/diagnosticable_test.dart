import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

final class _DiagnosticLeaf extends Seed {
  const _DiagnosticLeaf(this.label, {super.key});
  final String label;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty.string(
        name: 'label',
        level: DiagnosticsLevel.info,
        value: label,
      ),
    );
  }

  @override
  Branch createBranch() => _DiagnosticLeafBranch(this);
}

final class _DiagnosticLeafBranch extends Branch {
  _DiagnosticLeafBranch(super.seed);
}

final class _DiagnosticNode extends MultiChildSeed {
  const _DiagnosticNode(this.name, {super.children});
  final String name;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty.string(
        name: 'name',
        level: DiagnosticsLevel.info,
        value: name,
      ),
    );
  }
}

void main() {
  test(
    'Seed describes its concrete type, optional key, and subclass fields',
    () {
      expect(
        const _DiagnosticLeaf('plain').toStringDeep(),
        '_DiagnosticLeaf\n'
        '  seedType: _DiagnosticLeaf (info)\n'
        '  label: plain (info)\n',
      );
      expect(
        const _DiagnosticLeaf(
          'keyed',
          key: ValueKey<String>('leaf-key'),
        ).toStringDeep(),
        '_DiagnosticLeaf\n'
        '  seedType: _DiagnosticLeaf (info)\n'
        "  key: [ValueKey<String> <'leaf-key'>] (info)\n"
        '  label: keyed (info)\n',
      );
    },
  );

  test('unmounted Branch diagnostics do not read branchId', () {
    final branch = const _DiagnosticLeaf('detached').createBranch();
    expect(
      branch.toStringDeep(),
      '_DiagnosticLeafBranch\n'
      '  seedType: _DiagnosticLeaf (info)\n'
      '  label: detached (info)\n'
      '  mounted: false (info)\n'
      '  dirty: false (info)\n',
    );
  });

  test('mounted Branch renders its ordered diagnostic subtree', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(
      const _DiagnosticNode(
        'root',
        children: [
          _DiagnosticLeaf('first'),
          _DiagnosticNode('nested', children: [_DiagnosticLeaf('deep')]),
        ],
      ),
    );
    expect(
      root.toStringDeep(),
      'MultiChildBranch\n'
      '  seedType: _DiagnosticNode (info)\n'
      '  name: root (info)\n'
      '  mounted: true (info)\n'
      '  dirty: false (info)\n'
      '  branchId: 0 (info)\n'
      '  _DiagnosticLeafBranch\n'
      '    seedType: _DiagnosticLeaf (info)\n'
      '    label: first (info)\n'
      '    mounted: true (info)\n'
      '    dirty: false (info)\n'
      '    branchId: 1 (info)\n'
      '  MultiChildBranch\n'
      '    seedType: _DiagnosticNode (info)\n'
      '    name: nested (info)\n'
      '    mounted: true (info)\n'
      '    dirty: false (info)\n'
      '    branchId: 2 (info)\n'
      '    _DiagnosticLeafBranch\n'
      '      seedType: _DiagnosticLeaf (info)\n'
      '      label: deep (info)\n'
      '      mounted: true (info)\n'
      '      dirty: false (info)\n'
      '      branchId: 3 (info)\n',
    );
  });
}
