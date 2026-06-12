import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixture.g.dart';
import 'src/fixture_seeds.dart';

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

  group('buildSeedTree through the registry (seam 3)', () {
    test('component ids become Seed keys', () {
      final root = buildSeedTree(componentRegistry, v1) as Panel;
      expect(root.key, 'root');
      expect(root.name, 'dash');
      expect(root.children.map((c) => c.key), ['l1', 'g1']);
      expect(root.children[0], isA<Label>());
      expect(root.children[1], isA<Gauge>());
      expect((root.children[1] as Gauge).scale, 10); // catalog default
    });

    test('the built tree mounts under a TreeOwner', () {
      final owner = TreeOwner();
      final root =
          owner.mountRoot(buildSeedTree(componentRegistry, v1)) as PanelBranch;
      expect(root.children, hasLength(2));
      final visited = <Branch>[];
      root.visitChildren(visited.add);
      expect(visited[0], isA<LabelBranch>());
      expect(visited[1], isA<GaugeBranch>());
      expect(visited[0].key, 'l1');
      expect(visited[1].key, 'g1');
      owner.dispose();
    });

    test('re-emission reconciles to an identity-preserving patch by id', () {
      final owner = TreeOwner();
      final root =
          owner.mountRoot(buildSeedTree(componentRegistry, v1)) as PanelBranch;
      final labelBranch = root.children[0];
      final gaugeBranch = root.children[1];

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
      root.update(buildSeedTree(componentRegistry, v2));

      // Same branch instance for the surviving id, at its new index, with
      // the new config visible; the removed id unmounted; the inserted id
      // fresh and mounted.
      expect(identical(root.children[1], labelBranch), isTrue);
      expect((root.children[1].seed as Label).value, 'Nico Spencer');
      expect(gaugeBranch.mounted, isFalse);
      expect(root.children[0].key, 'l2');
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
      final seed = buildSeedTree(componentRegistry, components, rootId: 'main');
      expect(seed.key, 'main');
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
      final root = buildSeedTree(componentRegistry, components) as Panel;
      final p1 = root.children[0] as Panel;
      final p2 = root.children[1] as Panel;
      expect(p1.children.single.key, 'shared');
      expect(p2.children.single.key, 'shared');
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
        () => buildSeedTree(componentRegistry, components),
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
        () => buildSeedTree(componentRegistry, components),
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
        () => buildSeedTree(componentRegistry, components),
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
        () => buildSeedTree(componentRegistry, components),
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
        () => buildSeedTree(componentRegistry, components),
        throwsA(isA<UnknownComponentTypeException>()),
      );
    });
  });
}
