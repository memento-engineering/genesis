// DialogueSurface's root-compatibility guard and its metadata-commit order
// hold in RELEASE builds, so this file is run both ways in validation:
//   dart test test/surface_root_compat_test.dart   (assertions ON)
//   dart run  test/surface_root_compat_test.dart   (assertions OFF)
import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

import 'src/dialogue_fixture.g.dart';

UpdateComponents _nodeRoot(String surfaceId) => UpdateComponents(
  surfaceId: surfaceId,
  components: const [
    ComponentInstance(
      id: 'root',
      type: 'node',
      props: {'name': 'form'},
      childIds: ['f_name'],
    ),
    ComponentInstance(
      id: 'f_name',
      type: 'field',
      props: {'name': 'Name', 'value': 'Nico'},
    ),
  ],
);

UpdateComponents _fieldRoot(String surfaceId) => UpdateComponents(
  surfaceId: surfaceId,
  components: const [
    ComponentInstance(
      id: 'root',
      type: 'field',
      props: {'name': 'Name', 'value': 'Nico'},
    ),
  ],
);

class _ExplodingSeed extends Seed {
  const _ExplodingSeed({super.key});

  @override
  _ExplodingBranch createBranch() => _ExplodingBranch(this);
}

class _ExplodingBranch extends Branch {
  _ExplodingBranch(_ExplodingSeed super.seed);

  bool _built = false;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    if (_built) throw StateError('exploding branch: update failed');
    _built = true;
  }
}

final ComponentRegistry _explodingRegistry = ComponentRegistry(
  catalogName: 'exploding_fixture',
  catalogVersion: '0.1.0',
  entries: {
    'box': RegistryEntry(
      container: false,
      knownProps: const {},
      build: (props, children, key) => _ExplodingSeed(key: key),
    ),
  },
);

UpdateComponents _boxRoot(String surfaceId) => UpdateComponents(
  surfaceId: surfaceId,
  components: const [ComponentInstance(id: 'root', type: 'box')],
);

void main() {
  test('apply with an incompatible root throws and leaves the surface '
      'untouched', () {
    final surface = DialogueSurface(registry: componentRegistry);
    final root = surface.mount(_nodeRoot('main'));

    expect(
      () => surface.apply(_fieldRoot('second')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('incompatible root seed'),
        ),
      ),
    );

    expect(surface.surfaceId, 'main');
    expect(identical(surface.rootBranch, root), isTrue);
    expect(root.mounted, isTrue);
    expect((root.seed as Node).name, 'form');
  });

  test('a throwing update leaves the previous surface metadata intact', () {
    final surface = DialogueSurface(registry: _explodingRegistry);
    surface.mount(_boxRoot('main'));

    expect(
      () => surface.apply(_boxRoot('second')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('exploding branch'),
        ),
      ),
    );

    expect(surface.surfaceId, 'main');
  });

  test('a compatible re-emission still applies and commits the new id', () {
    final surface = DialogueSurface(registry: componentRegistry);
    final root = surface.mount(_nodeRoot('main'));

    surface.apply(_nodeRoot('second'));

    expect(surface.surfaceId, 'second');
    expect(identical(surface.rootBranch, root), isTrue);
  });
}
