import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

final class _DiagnosticLeaf extends Component {
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
  Element createElement() => _DiagnosticLeafElement(this);
}

final class _DiagnosticLeafElement extends Element {
  _DiagnosticLeafElement(super.component);
}

final class _DiagnosticNode extends MultiChildComponent {
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
    'Component describes its concrete type, optional key, and subclass fields',
    () {
      expect(
        const _DiagnosticLeaf('plain').toStringDeep(),
        '_DiagnosticLeaf\n'
        '  componentType: _DiagnosticLeaf (info)\n'
        '  label: plain (info)\n',
      );
      expect(
        const _DiagnosticLeaf(
          'keyed',
          key: ValueKey<String>('leaf-key'),
        ).toStringDeep(),
        '_DiagnosticLeaf\n'
        '  componentType: _DiagnosticLeaf (info)\n'
        "  key: [ValueKey<String> <'leaf-key'>] (info)\n"
        '  label: keyed (info)\n',
      );
    },
  );

  test('unmounted Element diagnostics do not read elementId', () {
    final element = const _DiagnosticLeaf('detached').createElement();
    expect(
      element.toStringDeep(),
      '_DiagnosticLeafElement\n'
      '  componentType: _DiagnosticLeaf (info)\n'
      '  label: detached (info)\n'
      '  mounted: false (info)\n'
      '  dirty: false (info)\n',
    );
  });

  test('mounted Element renders its ordered diagnostic subtree', () {
    final owner = BuildOwner();
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
      'MultiChildElement\n'
      '  componentType: _DiagnosticNode (info)\n'
      '  name: root (info)\n'
      '  mounted: true (info)\n'
      '  dirty: false (info)\n'
      '  elementId: 0 (info)\n'
      '  _DiagnosticLeafElement\n'
      '    componentType: _DiagnosticLeaf (info)\n'
      '    label: first (info)\n'
      '    mounted: true (info)\n'
      '    dirty: false (info)\n'
      '    elementId: 1 (info)\n'
      '  MultiChildElement\n'
      '    componentType: _DiagnosticNode (info)\n'
      '    name: nested (info)\n'
      '    mounted: true (info)\n'
      '    dirty: false (info)\n'
      '    elementId: 2 (info)\n'
      '    _DiagnosticLeafElement\n'
      '      componentType: _DiagnosticLeaf (info)\n'
      '      label: deep (info)\n'
      '      mounted: true (info)\n'
      '      dirty: false (info)\n'
      '      elementId: 3 (info)\n',
    );
  });
}
