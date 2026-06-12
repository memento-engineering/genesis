/// Flat keyed components -> `Seed` tree, parameterized over the registry
/// (ADR-0002 Decision 4 seam 3).
///
/// This is the deserialize half the wire package (`genesis_dialogue`) builds
/// on: it takes a [ComponentRegistry] as an argument and never imports a
/// generated file — the one line spike 5 had to fork is a parameter here.
/// Envelope parsing (the A2UI `updateComponents` message itself) is wire
/// vocabulary and stays out of this package; callers hand over the flat
/// component list they parsed.
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'errors.dart';
import 'registry_runtime.dart';

/// One entry of a flat keyed component list: the registry-facing shape of an
/// A2UI component, independent of any wire envelope.
class ComponentInstance {
  /// Creates an instance description.
  const ComponentInstance({
    required this.id,
    required this.type,
    this.props = const {},
    this.childIds = const [],
  });

  /// Stable component id — becomes the `Seed` key (the reconciliation
  /// identity; tree keys == A2UI component ids, ADR-0003).
  final String id;

  /// Wire type name (the `component` discriminator).
  final String type;

  /// Wire props for this instance.
  final Map<String, Object?> props;

  /// Ordered ids of child components (containers only).
  final List<String> childIds;
}

/// Builds a `Seed` tree from the flat [components] list through [registry].
///
/// Component ids become `Seed` keys, which is what lets keyed reconciliation
/// turn whole-tree re-emission into an identity-preserving patch. The root
/// is the component whose id is [rootId] (A2UI v0.9 convention: `'root'`).
///
/// Throws structured errors: [DuplicateComponentIdException],
/// [UnknownRootIdException], [DanglingChildIdException],
/// [ComponentCycleException] (tree shape), and the registry's
/// `ComponentBuildException`s (unknown type, bad props, children on a
/// leaf). A component reachable from two parents (a DAG share) is built
/// twice, not rejected; only true cycles are rejected.
Seed buildSeedTree(
  ComponentRegistry registry,
  List<ComponentInstance> components, {
  String rootId = 'root',
}) {
  final byId = <String, ComponentInstance>{};
  for (final component in components) {
    if (byId.containsKey(component.id)) {
      throw DuplicateComponentIdException(id: component.id);
    }
    byId[component.id] = component;
  }
  if (!byId.containsKey(rootId)) {
    throw UnknownRootIdException(
      rootId: rootId,
      knownIds: [for (final c in components) c.id],
    );
  }

  final visiting = <String>[];
  Seed build(String id, String? parentId) {
    final instance = byId[id];
    if (instance == null) {
      throw DanglingChildIdException(childId: id, parentId: parentId!);
    }
    if (visiting.contains(id)) {
      throw ComponentCycleException(path: [...visiting, id]);
    }
    visiting.add(id);
    final children = [
      for (final childId in instance.childIds) build(childId, id),
    ];
    visiting.removeLast();
    // Component id becomes the Seed key — the reconciliation identity.
    return registry.buildComponent(
      instance.type,
      instance.props,
      children,
      instance.id,
    );
  }

  return build(rootId, null);
}
