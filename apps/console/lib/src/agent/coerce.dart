import 'dart:convert';

/// Turns the model's `render` tool arguments into a full A2UI v0.9
/// `updateComponents` message ready for `Console.loadOrApply`.
///
/// Robust to the quirks local models exhibit without constrained decoding
/// (all observed live against swift-infer):
/// - the arguments blob, or the `components` value, may be a *stringified* JSON
///   value — reparse it;
/// - integer props (`start`) may arrive as numeric strings — coerce them;
/// - the model cannot emit the `screen` root (registry-only infrastructure), so
///   it is synthesised here around the model's top-level `content` container.
///
/// Throws [FormatException] with an actionable message on malformed input, so
/// the agent loop can feed the error back to the model to self-correct.
Map<String, Object?> toUpdateComponents(
  Object arguments, {
  String surfaceId = 'console',
}) {
  final args = _asMap(arguments, 'tool arguments');
  if (!args.containsKey('components')) {
    throw const FormatException('tool call is missing "components"');
  }
  final list = _asList(args['components'], 'components');
  final components = <Map<String, Object?>>[
    for (var i = 0; i < list.length; i++)
      _coerceComponent(_asMap(list[i], 'components[$i]')),
  ];
  if (components.isEmpty) {
    throw const FormatException(
      '"components" is empty — render at least one component',
    );
  }
  final byId = {for (final c in components) c['id']: c};
  // The host synthesises the screen root with the reserved id "root"; a
  // model-supplied "root" would collide. Reject it with self-correctable
  // feedback — the envelope parser's duplicate-id error would otherwise cite
  // phantom indices for a node the model never emitted.
  if (byId.containsKey('root')) {
    throw const FormatException(
      'id "root" is reserved for the host screen root — rename your top-level '
      'component to "content"',
    );
  }
  // "content" must be the real top of the tree, not merely present: a stray
  // component named "content" would otherwise become the whole UI while the
  // model's actual tree is silently dropped. Require it to exist, be a box,
  // and not be referenced as any other component's child.
  final content = byId['content'];
  if (content == null) {
    throw const FormatException(
      'the top-level container must be a box with id "content"; no component '
      'has id "content"',
    );
  }
  if (content['component'] != 'box') {
    throw FormatException(
      'the component with id "content" must be a "box" (the top-level '
      'container), but it is a "${content['component']}"',
    );
  }
  final childIds = <Object?>{
    for (final c in components)
      if (c['children'] case final List<Object?> kids) ...kids,
  };
  if (childIds.contains('content')) {
    throw const FormatException(
      'id "content" must be the top-level box; it must not be listed as '
      "another component's children",
    );
  }
  // Synthesise the screen root the model cannot address (it is not a catalog
  // type — see renderTool / the registry's hand-wired screen entry).
  components.insert(0, <String, Object?>{
    'id': 'root',
    'component': 'screen',
    'children': ['content'],
  });
  return {
    'version': 'v0.9',
    'updateComponents': {'surfaceId': surfaceId, 'components': components},
  };
}

/// Props the catalog declares as integers; coerced from a numeric string when a
/// model emits them as strings (a common no-constrained-decoding quirk). Kept
/// in sync with the catalog's `type: integer` leaf props — a drift-guard test
/// asserts this set covers every one.
const Set<String> coercedIntProps = {'start'};

Map<String, Object?> _coerceComponent(Map<String, Object?> component) {
  final out = <String, Object?>{...component};
  for (final key in coercedIntProps) {
    final value = out[key];
    if (value is String) {
      final n = int.tryParse(value.trim());
      if (n != null) out[key] = n;
    }
  }
  return out;
}

Map<String, Object?> _asMap(Object? value, String what) {
  final v = _maybeReparse(value);
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException(
    'expected $what to be a JSON object, got ${v.runtimeType}',
  );
}

List<Object?> _asList(Object? value, String what) {
  final v = _maybeReparse(value);
  if (v is List) return v;
  throw FormatException(
    'expected $what to be a JSON array, got ${v.runtimeType}',
  );
}

/// A value that should be a Map/List but arrived as a JSON string is reparsed;
/// a non-JSON string (or a parse failure) is returned unchanged so the caller's
/// type check raises a clear error.
Object? _maybeReparse(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonDecode(trimmed);
      } on FormatException {
        return value;
      }
    }
  }
  return value;
}
