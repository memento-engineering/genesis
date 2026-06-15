/// The A2UI v0.9 `updateComponents` envelope codec — the bidirectional
/// grammar of surface emission.
///
/// The wire shape, pure A2UI v0.9:
///
/// ```json
/// {
///   "version": "v0.9",
///   "updateComponents": {
///     "surfaceId": "main",
///     "components": [
///       {"id": "root", "component": "node", "name": "form",
///        "children": ["f1"]},
///       {"id": "f1", "component": "field", "name": "Name", "value": "Nico"}
///     ]
///   }
/// }
/// ```
///
/// Components are a flat adjacency list: `component` is the string type
/// discriminator, props sit directly on the component object (v0.9's flat
/// style), and `children` is an ordered array of component-id strings
/// (containers only). The root is the component with `id == "root"` — there
/// is **no** `rootId` field (the wire is pure v0.9).
///
/// [parseUpdateComponents] and [UpdateComponents.toJson] are a lossless
/// round-trip in both directions. The serialize direction **is** emission of
/// an authored surface ([UpdateComponents] → wire). Reverse-emission —
/// walking a live mounted `Seed`/`Branch` tree back into components — is
/// deliberately out of scope (it needs a taxonomy reverse-describer that does
/// not exist as built); see the package README's deferred list.
library;

import 'package:genesis_taxonomy/genesis_taxonomy.dart' show ComponentInstance;

import 'errors.dart';

/// The A2UI v0.9 wire version this codec speaks.
const String a2uiVersion = 'v0.9';

/// A parsed `updateComponents` message: the surface id plus the flat list of
/// component instances (the registry-facing shape, `ComponentInstance`, owned
/// by `genesis_taxonomy`).
///
/// This is the typed mirror of the envelope. The components are
/// `genesis_taxonomy`'s [ComponentInstance] — dialogue does not redefine the
/// instance shape; it parses the wire into it and hands it to
/// `buildSeedTree`.
final class UpdateComponents {
  /// Creates a parsed message. Prefer [parseUpdateComponents] from the wire.
  const UpdateComponents({required this.surfaceId, required this.components});

  /// Target surface id the components describe.
  final String surfaceId;

  /// The flat component instances, in wire order (root by `id == "root"`).
  final List<ComponentInstance> components;

  /// Serializes back to the A2UI v0.9 wire envelope — the emission direction.
  ///
  /// Lossless against [parseUpdateComponents]: props are written back at the
  /// top level of each component object, `children` is emitted only for
  /// containers that have children (an empty `children` is *not* re-emitted,
  /// matching the parse, which treats an absent and an empty `children`
  /// identically), and no `rootId` field is written.
  Map<String, Object?> toJson() => {
    'version': a2uiVersion,
    'updateComponents': {
      'surfaceId': surfaceId,
      'components': [
        for (final c in components)
          {
            'id': c.id,
            'component': c.type,
            ...c.props,
            if (c.childIds.isNotEmpty) 'children': [...c.childIds],
          },
      ],
    },
  };
}

/// Parses an A2UI v0.9 `updateComponents` envelope into [UpdateComponents].
///
/// Strict version policy (the wire is pure v0.9):
/// the `version` field must be present and equal to `v0.9`. A missing
/// version, or a v0.8 `surfaceUpdate`-keyed message, is rejected.
///
/// Envelope-level structural rejection (this layer's invariants), each via a
/// structured [EnvelopeException]:
///
/// - missing/non-`v0.9` `version` → [UnsupportedVersionException];
/// - missing/non-object `updateComponents` body →
///   [MissingUpdateComponentsException];
/// - non-string `surfaceId`, non-list `components`, non-object component
///   entry, non-string-list `children` → [EnvelopeFieldException];
/// - component missing/mistyped `id` or `component` →
///   [MalformedComponentException];
/// - duplicate component id → [DuplicateEnvelopeIdException].
///
/// It does **not** check dangling child ids, unknown types, or cycles — those
/// are `buildSeedTree`/registry invariants raised when the parsed instances
/// are built into a tree.
UpdateComponents parseUpdateComponents(Object json) {
  if (json is! Map) {
    throw EnvelopeFieldException(
      field: '',
      expected: 'a JSON object envelope',
      actual: json,
    );
  }
  final message = json.cast<String, Object?>();

  final version = message['version'];
  if (version != a2uiVersion) {
    throw UnsupportedVersionException(expected: a2uiVersion, actual: version);
  }

  final body = message['updateComponents'];
  if (body is! Map) {
    throw MissingUpdateComponentsException(presentKeys: message.keys.toList());
  }
  final bodyMap = body.cast<String, Object?>();

  final surfaceId = bodyMap['surfaceId'];
  if (surfaceId is! String) {
    throw EnvelopeFieldException(
      field: 'updateComponents.surfaceId',
      expected: 'a string',
      actual: surfaceId,
    );
  }

  final componentsRaw = bodyMap['components'];
  if (componentsRaw is! List) {
    throw EnvelopeFieldException(
      field: 'updateComponents.components',
      expected: 'a list of component objects',
      actual: componentsRaw,
    );
  }

  final firstIndexById = <String, int>{};
  final components = <ComponentInstance>[];
  for (var i = 0; i < componentsRaw.length; i++) {
    final raw = componentsRaw[i];
    if (raw is! Map) {
      throw MalformedComponentException(
        index: i,
        field: 'component',
        expected: 'a JSON object',
        actual: raw,
      );
    }
    final instance = _parseComponent(raw.cast<String, Object?>(), i);
    final firstIndex = firstIndexById[instance.id];
    if (firstIndex != null) {
      throw DuplicateEnvelopeIdException(
        id: instance.id,
        firstIndex: firstIndex,
        secondIndex: i,
      );
    }
    firstIndexById[instance.id] = i;
    components.add(instance);
  }

  return UpdateComponents(surfaceId: surfaceId, components: components);
}

/// Parses one flat component object into a [ComponentInstance].
ComponentInstance _parseComponent(Map<String, Object?> json, int index) {
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw MalformedComponentException(
      index: index,
      field: 'id',
      expected: 'a non-empty string',
      actual: id,
    );
  }
  final type = json['component'];
  if (type is! String || type.isEmpty) {
    throw MalformedComponentException(
      index: index,
      field: 'component',
      expected: 'a non-empty string (the type discriminator)',
      actual: type,
    );
  }

  var childIds = const <String>[];
  final childrenRaw = json['children'];
  if (childrenRaw != null) {
    if (childrenRaw is! List || childrenRaw.any((c) => c is! String)) {
      throw EnvelopeFieldException(
        field: 'updateComponents.components[$index].children',
        expected: 'a list of component-id strings',
        actual: childrenRaw,
      );
    }
    childIds = childrenRaw.cast<String>();
  }

  return ComponentInstance(
    id: id,
    type: type,
    // Every remaining top-level field is a prop (v0.9 flat-prop style).
    props: {
      for (final e in json.entries)
        if (e.key != 'id' && e.key != 'component' && e.key != 'children')
          e.key: e.value,
    },
    childIds: childIds,
  );
}
