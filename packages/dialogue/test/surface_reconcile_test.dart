import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

import 'src/dialogue_fixture.g.dart';

/// v1 surface: root node + 4 keyed children, mixing node/field, including a
/// nested subtree (n_addr → f_street).
Map<String, Object?> v1() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['f_name', 'f_email', 'n_addr', 'f_age'],
      },
      {'id': 'f_name', 'component': 'field', 'name': 'Name', 'value': 'Nico'},
      {
        'id': 'f_email',
        'component': 'field',
        'name': 'Email',
        'value': 'a@b.c',
      },
      {
        'id': 'n_addr',
        'component': 'node',
        'name': 'address',
        'children': ['f_street'],
      },
      {
        'id': 'f_street',
        'component': 'field',
        'name': 'Street',
        'value': '1 Main',
      },
      {'id': 'f_age', 'component': 'field', 'name': 'Age', 'value': '40'},
    ],
  },
};

/// v2 re-emission: f_name prop changed; f_age removed; f_phone inserted;
/// n_addr (3→1) and f_email (1→2) reordered; the nested f_street is carried
/// inside the moved n_addr subtree.
Map<String, Object?> v2() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['f_name', 'n_addr', 'f_email', 'f_phone'],
      },
      {
        'id': 'f_name',
        'component': 'field',
        'name': 'Name',
        'value': 'Nicholas',
      },
      {
        'id': 'n_addr',
        'component': 'node',
        'name': 'address',
        'children': ['f_street'],
      },
      {
        'id': 'f_street',
        'component': 'field',
        'name': 'Street',
        'value': '1 Main',
      },
      {
        'id': 'f_email',
        'component': 'field',
        'name': 'Email',
        'value': 'a@b.c',
      },
      {'id': 'f_phone', 'component': 'field', 'name': 'Phone', 'value': '555'},
    ],
  },
};

/// Returns the direct child of [node] whose Seed key equals [id].
Branch childById(NodeElement node, String id) =>
    node.children.firstWhere((c) => c.key == id);

void main() {
  group('mount: deserialize -> buildSeedTree -> mountRoot', () {
    test('tree structure, props, and component-id == Seed-key', () {
      final surface = DialogueSurface(registry: componentRegistry);
      final root = surface.mount(parseUpdateComponents(v1()));

      // root is a Node mounted by id "root".
      expect(root, isA<NodeElement>());
      expect(root.key, 'root');
      expect((root.seed as Node).name, 'form');

      final rootEl = root as NodeElement;
      expect(rootEl.children.map((c) => c.key), [
        'f_name',
        'f_email',
        'n_addr',
        'f_age',
      ]);

      // A leaf field: props landed.
      final name = childById(rootEl, 'f_name') as FieldElement;
      expect(name.field.name, 'Name');
      expect(name.field.value, 'Nico');

      // The nested subtree: n_addr -> f_street.
      final addr = childById(rootEl, 'n_addr') as NodeElement;
      expect(addr.children.single.key, 'f_street');
      final street = addr.children.single as FieldElement;
      expect(street.field.value, '1 Main');

      // Every component id surfaced as the Seed key.
      expect(name.seed.key, 'f_name');
      expect(addr.seed.key, 'n_addr');
    });
  });

  group(
    'reconcile by key (the crux: identity preserved across re-emission)',
    () {
      test(
        'kept ids = same Branch; prop-change = same Branch; remove unmounts; '
        'insert is fresh; deep identity in a moved subtree',
        () {
          final surface = DialogueSurface(registry: componentRegistry);
          final root =
              surface.mount(parseUpdateComponents(v1())) as NodeElement;

          // Capture v1 instances.
          final nameBefore = childById(root, 'f_name');
          final emailBefore = childById(root, 'f_email');
          final addrBefore = childById(root, 'n_addr') as NodeElement;
          final ageBefore = childById(root, 'f_age');
          final streetBefore =
              addrBefore.children.single; // deep, inside n_addr

          surface.apply(parseUpdateComponents(v2()));

          // Root survived (stable key "root", canUpdate held).
          expect(identical(surface.rootBranch, root), isTrue);
          expect(root.mounted, isTrue);

          final nameAfter = childById(root, 'f_name');
          final emailAfter = childById(root, 'f_email');
          final addrAfter = childById(root, 'n_addr') as NodeElement;
          final phoneAfter = childById(root, 'f_phone');

          // New child order reflects the re-emission.
          expect(root.children.map((c) => c.key), [
            'f_name',
            'n_addr',
            'f_email',
            'f_phone',
          ]);

          // Prop-changed id: SAME instance, new seed/props.
          expect(identical(nameAfter, nameBefore), isTrue);
          expect((nameAfter as FieldElement).field.value, 'Nicholas');

          // Reordered ids: SAME instances at their new index.
          expect(identical(emailAfter, emailBefore), isTrue);
          expect(identical(addrAfter, addrBefore), isTrue);

          // DEEP identity: f_street nested inside the moved n_addr subtree.
          final streetAfter = addrAfter.children.single;
          expect(identical(streetAfter, streetBefore), isTrue);

          // Removed id: old instance unmounted.
          expect(ageBefore.mounted, isFalse);

          // Inserted id: fresh, mounted, distinct from every v1 instance.
          expect(phoneAfter.mounted, isTrue);
          expect(identical(phoneAfter, ageBefore), isFalse);
        },
      );
    },
  );

  group('A18 honest-limit (the wire path does not benefit from the skip)', () {
    test('re-applying a structurally-identical v2 still reconciles by key, '
        'yet identity is still preserved', () {
      final surface = DialogueSurface(registry: componentRegistry);
      final root = surface.mount(parseUpdateComponents(v1())) as NodeElement;
      surface.apply(parseUpdateComponents(v2()));

      final nameBranch = childById(root, 'f_name');
      final addrBranch = childById(root, 'n_addr') as NodeElement;
      final streetBranch = addrBranch.children.single;
      final nameSeedBefore = nameBranch.seed;

      // Re-apply a freshly-deserialized, byte-identical v2. Fresh seeds are
      // never identical() to the mounted ones, so the A18 fast path does
      // NOT fire — update() runs and swaps the seed instance...
      surface.apply(parseUpdateComponents(v2()));

      // ...the seed object IS a new instance (the skip did not short-circuit)
      expect(
        identical(childById(root, 'f_name').seed, nameSeedBefore),
        isFalse,
      );

      // ...yet keyed identity preservation still holds: same Branch
      // instances, including deep into the n_addr subtree.
      expect(identical(childById(root, 'f_name'), nameBranch), isTrue);
      final addrAfter = childById(root, 'n_addr') as NodeElement;
      expect(identical(addrAfter, addrBranch), isTrue);
      expect(identical(addrAfter.children.single, streetBranch), isTrue);
    });
  });
}
