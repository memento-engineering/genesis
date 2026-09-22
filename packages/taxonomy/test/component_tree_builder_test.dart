import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixture.g.dart';
import 'src/fixture_components.dart';

void main() {
  const v1 = [
    ComponentInstance(
      id: 'root',
      type: 'panel',
      props: {'name': 'dash'},
      childIds: ['l1', 'g1'],
    ),
    ComponentInstance(
      id: 'l1',
      type: 'label',
      props: {'name': 'Name', 'value': 'Nico'},
    ),
    ComponentInstance(
      id: 'g1',
      type: 'gauge',
      props: {'label': 'Fuel', 'value': 3.5},
    ),
  ];

  group('buildComponentTree through the registry (seam 3)', () {
    test('component ids become Component keys', () {
      final root = buildComponentTree(componentRegistry, v1) as Panel;
      expect(root.key, const ValueKey('root'));
      expect(root.name, 'dash');
      expect(root.children.map((c) => c.key), const [
        ValueKey('l1'),
        ValueKey('g1'),
      ]);
      expect(root.children[0], isA<Label>());
      expect(root.children[1], isA<Gauge>());
      expect((root.children[1] as Gauge).scale, 10); // catalog default
    });

    test('the built tree mounts under a BuildOwner', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(buildComponentTree(componentRegistry, v1))
              as PanelElement;
      expect(root.children, hasLength(2));
      final visited = <Element>[];
      root.visitChildren(visited.add);
      expect(visited[0], isA<LabelElement>());
      expect(visited[1], isA<GaugeElement>());
      expect(visited[0].key, const ValueKey('l1'));
      expect(visited[1].key, const ValueKey('g1'));
      owner.dispose();
    });

    test('re-emission reconciles to an identity-preserving patch by id', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(buildComponentTree(componentRegistry, v1))
              as PanelElement;
      final labelElement = root.children[0];
      final gaugeElement = root.children[1];

      // v2: l1 prop changed, g1 removed, l2 inserted, order l2 before l1.
      const v2 = [
        ComponentInstance(
          id: 'root',
          type: 'panel',
          props: {'name': 'dash'},
          childIds: ['l2', 'l1'],
        ),
        ComponentInstance(
          id: 'l2',
          type: 'label',
          props: {'name': 'Role', 'value': 'keeper'},
        ),
        ComponentInstance(
          id: 'l1',
          type: 'label',
          props: {'name': 'Name', 'value': 'Nico Spencer'},
        ),
      ];
      root.update(buildComponentTree(componentRegistry, v2));

      // Same element instance for the surviving id, at its new index, with
      // the new config visible; the removed id unmounted; the inserted id
      // fresh and mounted.
      expect(identical(root.children[1], labelElement), isTrue);
      expect((root.children[1].component as Label).value, 'Nico Spencer');
      expect(gaugeElement.mounted, isFalse);
      expect(root.children[0].key, const ValueKey('l2'));
      expect(root.children[0].mounted, isTrue);
      owner.dispose();
    });

    test('rootId can be overridden', () {
      const components = [
        ComponentInstance(
          id: 'main',
          type: 'label',
          props: {'name': 'n', 'value': 'v'},
        ),
      ];
      final component = buildComponentTree(
        componentRegistry,
        components,
        rootId: 'main',
      );
      expect(component.key, const ValueKey('main'));
    });

    test('a DAG share builds twice rather than rejecting', () {
      const components = [
        ComponentInstance(
          id: 'root',
          type: 'panel',
          props: {'name': 'outer'},
          childIds: ['p1', 'p2'],
        ),
        ComponentInstance(
          id: 'p1',
          type: 'panel',
          props: {'name': 'one'},
          childIds: ['shared'],
        ),
        ComponentInstance(
          id: 'p2',
          type: 'panel',
          props: {'name': 'two'},
          childIds: ['shared'],
        ),
        ComponentInstance(
          id: 'shared',
          type: 'label',
          props: {'name': 'n', 'value': 'v'},
        ),
      ];
      final root = buildComponentTree(componentRegistry, components) as Panel;
      final p1 = root.children[0] as Panel;
      final p2 = root.children[1] as Panel;
      expect(p1.children.single.key, const ValueKey('shared'));
      expect(p2.children.single.key, const ValueKey('shared'));
    });
  });

  group('structured tree-shape errors', () {
    test('duplicate component id', () {
      const components = [
        ComponentInstance(
          id: 'root',
          type: 'label',
          props: {'name': 'n', 'value': 'v'},
        ),
        ComponentInstance(
          id: 'root',
          type: 'label',
          props: {'name': 'n', 'value': 'v'},
        ),
      ];
      expect(
        () => buildComponentTree(componentRegistry, components),
        throwsA(
          isA<DuplicateComponentIdException>().having(
            (e) => e.id,
            'id',
            'root',
          ),
        ),
      );
    });

    test('unknown root id', () {
      const components = [
        ComponentInstance(
          id: 'a',
          type: 'label',
          props: {'name': 'n', 'value': 'v'},
        ),
      ];
      expect(
        () => buildComponentTree(componentRegistry, components),
        throwsA(
          isA<UnknownRootIdException>()
              .having((e) => e.rootId, 'rootId', 'root')
              .having((e) => e.knownIds, 'knownIds', ['a']),
        ),
      );
    });

    test('dangling child id names the referencing parent', () {
      const components = [
        ComponentInstance(
          id: 'root',
          type: 'panel',
          props: {'name': 'dash'},
          childIds: ['ghost'],
        ),
      ];
      expect(
        () => buildComponentTree(componentRegistry, components),
        throwsA(
          isA<DanglingChildIdException>()
              .having((e) => e.childId, 'childId', 'ghost')
              .having((e) => e.parentId, 'parentId', 'root'),
        ),
      );
    });

    test('a cycle reports the id path', () {
      const components = [
        ComponentInstance(
          id: 'root',
          type: 'panel',
          props: {'name': 'a'},
          childIds: ['b'],
        ),
        ComponentInstance(
          id: 'b',
          type: 'panel',
          props: {'name': 'b'},
          childIds: ['root'],
        ),
      ];
      expect(
        () => buildComponentTree(componentRegistry, components),
        throwsA(
          isA<ComponentCycleException>().having((e) => e.path, 'path', [
            'root',
            'b',
            'root',
          ]),
        ),
      );
    });

    test('registry construction errors propagate through the builder', () {
      const components = [ComponentInstance(id: 'root', type: 'toggle')];
      expect(
        () => buildComponentTree(componentRegistry, components),
        throwsA(isA<UnknownComponentTypeException>()),
      );
    });
  });
}
