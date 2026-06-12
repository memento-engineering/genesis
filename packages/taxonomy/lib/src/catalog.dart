/// The parsed, validated catalog document (ADR-0002).
///
/// A catalog classifies the node species of one domain: each [CatalogType]
/// declares its wire name, typed props, container/leaf shape, Dart binding,
/// and (via the extension seam) extension data such as action declarations.
/// `Catalog.parse` validates the whole document loudly — malformed catalogs
/// throw structured [CatalogException]s instead of generating silently-wrong
/// code.
library;

import 'dart:convert';

import 'errors.dart';
import 'extension.dart';

/// Wire-level prop types a catalog may declare (JSON Schema vocabulary).
enum PropType {
  /// JSON string.
  string('string'),

  /// JSON integer (a whole number; `3.5` is rejected).
  integer('integer'),

  /// JSON number (binds to Dart `double`; integral values are accepted and
  /// widened).
  number('number'),

  /// JSON boolean.
  boolean('boolean'),

  /// A closed set of string values declared by the prop's `values` list.
  enumeration('enum');

  const PropType(this.wireName);

  /// The name used in the catalog document and the tool schema.
  final String wireName;

  /// Parses a catalog `type` value; null when [raw] names no prop type.
  static PropType? fromWireName(String raw) {
    for (final t in PropType.values) {
      if (t.wireName == raw) return t;
    }
    return null;
  }
}

/// One typed prop declaration on a catalog type.
class CatalogProp {
  /// Creates a prop declaration. [defaultValue] is non-null iff the prop is
  /// optional ([required] false); [enumValues] is non-null iff [type] is
  /// [PropType.enumeration].
  const CatalogProp({
    required this.name,
    required this.type,
    required this.required,
    required this.description,
    this.defaultValue,
    this.enumValues,
  });

  /// Wire prop name.
  final String name;

  /// Wire type of the prop value.
  final PropType type;

  /// Whether the prop must be present on every component instance. Optional
  /// props always carry a [defaultValue] (the catalog format rejects
  /// optional-without-default).
  final bool required;

  /// Description, flowing through to the tool schema verbatim.
  final String description;

  /// The default applied when an optional prop is absent; null for required
  /// props.
  final Object? defaultValue;

  /// Allowed values, in catalog order; null unless [type] is
  /// [PropType.enumeration].
  final List<String>? enumValues;
}

/// How a catalog type binds to a Dart `Seed` constructor.
class DartBinding {
  /// Creates a binding; [childrenParam] is non-null iff the owning type is a
  /// container.
  const DartBinding({
    required this.className,
    required this.import,
    required this.positionalProps,
    required this.namedProps,
    this.childrenParam,
  });

  /// The Dart class to construct (a `Seed` subclass).
  final String className;

  /// Import URI for [className] — `package:` or relative to the generated
  /// file.
  final String import;

  /// Props passed positionally, in parameter order.
  final List<String> positionalProps;

  /// Props passed as named arguments.
  final List<String> namedProps;

  /// Named parameter receiving the children list (containers only).
  final String? childrenParam;
}

/// One node species: a wire type name plus its traits.
class CatalogType {
  /// Creates a parsed catalog type.
  const CatalogType({
    required this.name,
    required this.description,
    required this.container,
    required this.props,
    required this.dart,
    required this.extensions,
  });

  /// Wire type name (the `component` discriminator on the wire).
  final String name;

  /// Description, flowing through to the tool schema verbatim.
  final String description;

  /// Whether instances may carry children. Leaves reject children at
  /// construction.
  final bool container;

  /// Declared props, in catalog order.
  final List<CatalogProp> props;

  /// The Dart constructor binding.
  final DartBinding dart;

  /// Extension-parsed extension data, keyed by the catalog key the extension
  /// claimed (ADR-0002 Decision 4 seam 1).
  final Map<String, Object> extensions;

  /// Type-level action declarations (the affordance channel, ADR-0005),
  /// parsed by [ActionsCatalogExtension]; empty when the type declares none.
  Map<String, ActionDeclaration> get actions {
    final raw = extensions[ActionsCatalogExtension.catalogKey];
    if (raw == null) return const {};
    return raw as Map<String, ActionDeclaration>;
  }

  /// The prop declared as [name], or null.
  CatalogProp? propNamed(String name) {
    for (final p in props) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// A parsed, validated catalog document: provenance block + node types +
/// the extensions it was parsed with.
class Catalog {
  /// Creates a parsed catalog. Prefer [Catalog.parse].
  const Catalog({
    required this.name,
    required this.version,
    required this.types,
    required this.extensions,
    this.description,
  });

  /// Catalog name from the provenance block; parameterizes every generated
  /// header (ADR-0002 Decision 4 seam 2).
  final String name;

  /// Catalog version from the provenance block.
  final String version;

  /// Optional provenance description.
  final String? description;

  /// Node types, sorted by name (the deterministic emit order).
  final List<CatalogType> types;

  /// The extensions this catalog was parsed with; emitters replay their
  /// projection hooks.
  final List<CatalogExtension> extensions;

  /// The type named [name], or null.
  CatalogType? typeNamed(String name) {
    for (final t in types) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// Parses and validates a raw catalog JSON document.
  ///
  /// Unknown type-level keys must be claimed by a extension in [extensions] or the
  /// parse throws [UnhandledCatalogKeysException] listing every unhandled
  /// key (the loud-extension-key seam). Structural problems throw
  /// [CatalogFormatException] with the document path.
  static Catalog parse(
    String catalogJson, {
    List<CatalogExtension> extensions = defaultCatalogExtensions,
  }) {
    final extensionByKey = _indexExtensions(extensions);

    final Object? decoded;
    try {
      decoded = jsonDecode(catalogJson);
    } on FormatException catch (e) {
      throw CatalogFormatException(
        path: '',
        expected: 'a JSON document',
        actual: 'unparseable JSON (${e.message})',
      );
    }
    final root = _requireMap(decoded, '', 'the catalog document');

    _knownKeysOnly(root, '', const {r'$comment', 'catalog', 'types'});

    final provenance = _requireMap(
      root['catalog'],
      'catalog',
      'the catalog provenance block ({"name", "version", ...})',
    );
    _knownKeysOnly(provenance, 'catalog', const {
      r'$comment',
      'description',
      'name',
      'version',
    });
    final name = _requireString(provenance['name'], 'catalog/name');
    final version = _requireString(provenance['version'], 'catalog/version');
    final description = provenance['description'] == null
        ? null
        : _requireString(provenance['description'], 'catalog/description');

    final typesRaw = _requireMap(
      root['types'],
      'types',
      'the map of node types',
    );
    if (typesRaw.isEmpty) {
      throw const CatalogFormatException(
        path: 'types',
        expected: 'at least one node type',
        actual: '{}',
      );
    }

    final unhandledByType = <String, List<String>>{};
    final typeNames = typesRaw.keys.toList()..sort();
    final types = <CatalogType>[
      for (final typeName in typeNames)
        _parseType(
          typeName,
          _requireMap(typesRaw[typeName], 'types/$typeName', 'a type object'),
          extensionByKey,
          unhandledByType,
        ),
    ];

    if (unhandledByType.isNotEmpty) {
      throw UnhandledCatalogKeysException(
        unhandledKeysByType: unhandledByType,
        registeredExtensions: [for (final p in extensions) p.name],
      );
    }

    return Catalog(
      name: name,
      version: version,
      description: description,
      types: types,
      extensions: extensions,
    );
  }
}

/// Type-level keys the core parser owns; everything else rides the extension
/// seam.
const Set<String> _coreTypeKeys = {
  r'$comment',
  'container',
  'dart',
  'description',
  'props',
};

Map<String, CatalogExtension> _indexExtensions(
  List<CatalogExtension> extensions,
) {
  final byKey = <String, CatalogExtension>{};
  for (final extension in extensions) {
    for (final key in extension.typeKeys) {
      if (_coreTypeKeys.contains(key)) {
        throw CatalogFormatException(
          path: 'extensions',
          expected:
              'extension keys outside the core set '
              '(${_coreTypeKeys.join(', ')})',
          actual: 'extension "${extension.name}" claims core key "$key"',
        );
      }
      final existing = byKey[key];
      if (existing != null) {
        throw CatalogFormatException(
          path: 'extensions',
          expected: 'each type-level key claimed by at most one extension',
          actual:
              'key "$key" claimed by both "${existing.name}" and '
              '"${extension.name}"',
        );
      }
      byKey[key] = extension;
    }
  }
  return byKey;
}

CatalogType _parseType(
  String typeName,
  Map<String, Object?> json,
  Map<String, CatalogExtension> extensionByKey,
  Map<String, List<String>> unhandledByType,
) {
  final path = 'types/$typeName';
  final description = _requireString(json['description'], '$path/description');
  final container = _requireBool(json['container'], '$path/container');

  final propsRaw = _requireMap(
    json['props'],
    '$path/props',
    'the props map (may be empty)',
  );
  final props = <CatalogProp>[
    for (final propName in propsRaw.keys)
      _parseProp(
        propName,
        _requireMap(
          propsRaw[propName],
          '$path/props/$propName',
          'a prop object',
        ),
        '$path/props/$propName',
      ),
  ];

  final dart = _parseDartBinding(
    _requireMap(json['dart'], '$path/dart', 'the dart binding object'),
    '$path/dart',
    container: container,
    propNames: {for (final p in props) p.name},
  );

  // The extension seam (ADR-0002 Decision 4 seam 1): every non-core key is
  // routed to the extension that claims it; unclaimed keys are collected and
  // reported loudly, never dropped.
  final extensions = <String, Object>{};
  for (final key in json.keys) {
    if (_coreTypeKeys.contains(key)) continue;
    final extension = extensionByKey[key];
    if (extension == null) {
      unhandledByType.putIfAbsent(typeName, () => []).add(key);
      continue;
    }
    extensions[key] = extension.parseTypeValue(
      typeName: typeName,
      key: key,
      value: json[key],
    );
  }

  return CatalogType(
    name: typeName,
    description: description,
    container: container,
    props: props,
    dart: dart,
    extensions: extensions,
  );
}

CatalogProp _parseProp(
  String propName,
  Map<String, Object?> json,
  String path,
) {
  _knownKeysOnly(json, path, const {
    r'$comment',
    'default',
    'description',
    'required',
    'type',
    'values',
  });
  final typeRaw = _requireString(json['type'], '$path/type');
  final type = PropType.fromWireName(typeRaw);
  if (type == null) {
    throw CatalogFormatException(
      path: '$path/type',
      expected:
          'one of ${PropType.values.map((t) => '"${t.wireName}"').join(', ')}',
      actual: typeRaw,
    );
  }
  final required = _requireBool(json['required'], '$path/required');
  final description = _requireString(json['description'], '$path/description');

  List<String>? enumValues;
  if (type == PropType.enumeration) {
    final valuesRaw = json['values'];
    if (valuesRaw is! List ||
        valuesRaw.isEmpty ||
        valuesRaw.any((v) => v is! String)) {
      throw CatalogFormatException(
        path: '$path/values',
        expected: 'a non-empty list of strings (the allowed enum values)',
        actual: valuesRaw,
      );
    }
    enumValues = valuesRaw.cast<String>();
  } else if (json.containsKey('values')) {
    throw CatalogFormatException(
      path: '$path/values',
      expected: 'no "values" key on a non-enum prop',
      actual: json['values'],
    );
  }

  final defaultValue = json['default'];
  if (required) {
    if (json.containsKey('default')) {
      throw CatalogFormatException(
        path: '$path/default',
        expected: 'no default on a required prop',
        actual: defaultValue,
      );
    }
  } else {
    if (defaultValue == null) {
      throw CatalogFormatException(
        path: '$path/default',
        expected:
            'a default value — optional props must declare one '
            '(optional-without-default is rejected)',
      );
    }
    _checkDefaultType(type, defaultValue, enumValues, '$path/default');
  }

  return CatalogProp(
    name: propName,
    type: type,
    required: required,
    description: description,
    defaultValue: required ? null : defaultValue,
    enumValues: enumValues,
  );
}

void _checkDefaultType(
  PropType type,
  Object value,
  List<String>? enumValues,
  String path,
) {
  final ok = switch (type) {
    PropType.string => value is String,
    PropType.integer => value is int,
    PropType.number => value is num,
    PropType.boolean => value is bool,
    PropType.enumeration => value is String && enumValues!.contains(value),
  };
  if (!ok) {
    final expected = switch (type) {
      PropType.string => 'a string default',
      PropType.integer => 'an integer default',
      PropType.number => 'a number default',
      PropType.boolean => 'a boolean default',
      PropType.enumeration =>
        'one of the declared enum values '
            '(${enumValues!.map((v) => '"$v"').join(', ')})',
    };
    throw CatalogFormatException(path: path, expected: expected, actual: value);
  }
}

DartBinding _parseDartBinding(
  Map<String, Object?> json,
  String path, {
  required bool container,
  required Set<String> propNames,
}) {
  _knownKeysOnly(json, path, const {
    r'$comment',
    'childrenParam',
    'class',
    'import',
    'namedProps',
    'positionalProps',
  });
  final className = _requireString(json['class'], '$path/class');
  final import = _requireString(json['import'], '$path/import');
  final positional = _requireStringList(
    json['positionalProps'],
    '$path/positionalProps',
  );
  final named = _requireStringList(json['namedProps'], '$path/namedProps');
  final childrenParam = json['childrenParam'] == null
      ? null
      : _requireString(json['childrenParam'], '$path/childrenParam');

  if (container && childrenParam == null) {
    throw CatalogFormatException(
      path: '$path/childrenParam',
      expected: 'container types declare dart.childrenParam',
    );
  }
  if (!container && childrenParam != null) {
    throw CatalogFormatException(
      path: '$path/childrenParam',
      expected: 'no childrenParam on a leaf type',
      actual: childrenParam,
    );
  }

  final declared = [...positional, ...named];
  final declaredSet = declared.toSet();
  if (declared.length != declaredSet.length ||
      declaredSet.length != propNames.length ||
      !propNames.every(declaredSet.contains)) {
    throw CatalogFormatException(
      path: path,
      expected:
          'positionalProps + namedProps covering exactly the declared props '
          '(${(propNames.toList()..sort()).join(', ')}) with no duplicates',
      actual: declared,
    );
  }

  return DartBinding(
    className: className,
    import: import,
    positionalProps: positional,
    namedProps: named,
    childrenParam: childrenParam,
  );
}

// --- shared shape requirements -------------------------------------------

Map<String, Object?> _requireMap(Object? value, String path, String what) {
  if (value is Map) return value.cast<String, Object?>();
  throw CatalogFormatException(path: path, expected: what, actual: value);
}

String _requireString(Object? value, String path) {
  if (value is String && value.isNotEmpty) return value;
  throw CatalogFormatException(
    path: path,
    expected: 'a non-empty string',
    actual: value,
  );
}

bool _requireBool(Object? value, String path) {
  if (value is bool) return value;
  throw CatalogFormatException(
    path: path,
    expected: 'a boolean',
    actual: value,
  );
}

List<String> _requireStringList(Object? value, String path) {
  if (value is List && value.every((v) => v is String)) {
    return value.cast<String>();
  }
  throw CatalogFormatException(
    path: path,
    expected: 'a list of strings',
    actual: value,
  );
}

void _knownKeysOnly(Map<String, Object?> json, String path, Set<String> known) {
  for (final key in json.keys) {
    if (!known.contains(key)) {
      throw CatalogFormatException(
        path: path.isEmpty ? key : '$path/$key',
        expected:
            'one of the known keys (${(known.toList()..sort()).join(', ')})',
        actual: 'unknown key "$key"',
      );
    }
  }
}
