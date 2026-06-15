/// Structured error hierarchy for genesis_taxonomy.
///
/// Every failure mode is a sealed-union member carrying structured fields
/// (component type, prop name, expected/actual, ...) so an agent loop can
/// feed [TaxonomyException.message] back to an LLM verbatim, or switch
/// exhaustively over the kinds. Nothing here throws bare [StateError].
library;

/// Root of the genesis_taxonomy error union.
///
/// Three sub-families, each sealed for exhaustive switching:
///
/// - [CatalogException] — the catalog document itself is malformed
///   (authoring time; fails the generator run).
/// - [ComponentBuildException] — a component construction request violated
///   the catalog contract (runtime; the LLM-feedback channel).
/// - [TreeShapeException] — a flat component list does not form a tree
///   (runtime; the LLM-feedback channel).
sealed class TaxonomyException implements Exception {
  const TaxonomyException();

  /// Human/LLM-readable description assembled from the structured fields.
  /// Designed to be fed back to an LLM agent verbatim.
  String get message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Catalog (authoring-time) errors
// ---------------------------------------------------------------------------

/// The catalog document is malformed; raised while parsing/validating a
/// catalog, before any code is generated.
sealed class CatalogException extends TaxonomyException {
  const CatalogException();
}

/// A catalog value has the wrong shape at a specific document path.
final class CatalogFormatException extends CatalogException {
  /// Creates a format error at [path], stating [expected] versus [actual].
  const CatalogFormatException({
    required this.path,
    required this.expected,
    this.actual,
  });

  /// Slash-separated path into the catalog document, e.g.
  /// `types/gauge/props/value/default`.
  final String path;

  /// What the catalog format requires at [path].
  final String expected;

  /// What the document actually contained (null when absence is the error).
  final Object? actual;

  @override
  String get message =>
      'catalog error at "$path": expected $expected, got '
      '${actual == null ? 'nothing' : '$actual (${actual.runtimeType})'}';
}

/// One or more type-level catalog keys were claimed by no registered extension.
///
/// This is the loud-extension-key seam: unknown
/// type-level keys are never silently dropped — either a registered
/// [CatalogExtension] handles the key or parsing fails with this error listing
/// every unhandled key.
final class UnhandledCatalogKeysException extends CatalogException {
  /// Creates the error from the collected unhandled keys.
  const UnhandledCatalogKeysException({
    required this.unhandledKeysByType,
    required this.registeredExtensions,
  });

  /// Catalog type name -> the type-level keys nothing handled, in catalog
  /// order.
  final Map<String, List<String>> unhandledKeysByType;

  /// Names of the extensions that were registered for this parse.
  final List<String> registeredExtensions;

  @override
  String get message {
    final lines = [
      for (final e in unhandledKeysByType.entries)
        'type "${e.key}": ${e.value.map((k) => '"$k"').join(', ')}',
    ];
    final extensions = registeredExtensions.isEmpty
        ? 'none'
        : registeredExtensions.join(', ');
    return 'catalog declares type-level keys no registered extension handles — '
        '${lines.join('; ')}. Registered extensions: $extensions. Register a '
        'CatalogExtension claiming the key(s) or remove them from the catalog.';
  }
}

// ---------------------------------------------------------------------------
// Component construction (registry) errors
// ---------------------------------------------------------------------------

/// A component construction request violated the catalog contract. Thrown by
/// the generated registry at construction time; the structured fields are the
/// payload of the LLM feedback loop.
sealed class ComponentBuildException extends TaxonomyException {
  const ComponentBuildException();

  /// The wire component type the request named.
  String get componentType;
}

/// The requested component type does not exist in the catalog.
final class UnknownComponentTypeException extends ComponentBuildException {
  /// Creates the error for [componentType], listing [knownTypes].
  const UnknownComponentTypeException({
    required this.componentType,
    required this.knownTypes,
  });

  @override
  final String componentType;

  /// Every type the registry knows, sorted.
  final List<String> knownTypes;

  @override
  String get message =>
      'unknown component type "$componentType"; known types: '
      '${knownTypes.join(', ')}';
}

/// A prop was supplied that the component type does not declare.
final class UnknownPropException extends ComponentBuildException {
  /// Creates the error for [prop] on [componentType], listing [knownProps].
  const UnknownPropException({
    required this.componentType,
    required this.prop,
    required this.knownProps,
  });

  @override
  final String componentType;

  /// The undeclared prop name supplied.
  final String prop;

  /// Every prop the type declares, sorted.
  final List<String> knownProps;

  @override
  String get message =>
      'component type "$componentType": unknown prop "$prop"; declared '
      'props: ${knownProps.isEmpty ? '(none)' : knownProps.join(', ')}';
}

/// A required prop was absent (or explicit null) in the construction request.
final class MissingRequiredPropException extends ComponentBuildException {
  /// Creates the error for the missing [prop] of [expectedType].
  const MissingRequiredPropException({
    required this.componentType,
    required this.prop,
    required this.expectedType,
  });

  @override
  final String componentType;

  /// The missing prop name.
  final String prop;

  /// The wire type the prop requires (`string`, `integer`, `number`,
  /// `boolean`, or `enum`).
  final String expectedType;

  @override
  String get message =>
      'component type "$componentType": missing required prop "$prop" '
      '(expected $expectedType)';
}

/// A prop value had the wrong wire type.
final class PropTypeMismatchException extends ComponentBuildException {
  /// Creates the error for [prop] expecting [expectedType] but receiving
  /// [actualValue].
  const PropTypeMismatchException({
    required this.componentType,
    required this.prop,
    required this.expectedType,
    required this.actualValue,
  });

  @override
  final String componentType;

  /// The mistyped prop name.
  final String prop;

  /// The wire type the prop requires.
  final String expectedType;

  /// The value actually supplied.
  final Object? actualValue;

  @override
  String get message =>
      'component type "$componentType": prop "$prop" must be '
      '$expectedType, got ${actualValue.runtimeType} ($actualValue)';
}

/// An enum prop value is not one of the declared values.
final class InvalidEnumValueException extends ComponentBuildException {
  /// Creates the error for [prop] receiving [actualValue] outside
  /// [allowedValues].
  const InvalidEnumValueException({
    required this.componentType,
    required this.prop,
    required this.allowedValues,
    required this.actualValue,
  });

  @override
  final String componentType;

  /// The enum prop name.
  final String prop;

  /// The values the catalog declares for this enum, in catalog order.
  final List<String> allowedValues;

  /// The out-of-set value actually supplied.
  final Object? actualValue;

  @override
  String get message =>
      'component type "$componentType": prop "$prop" must be one of '
      '${allowedValues.map((v) => '"$v"').join(', ')}; got $actualValue';
}

/// Children were supplied to a leaf (non-container) component type.
final class ChildrenOnLeafException extends ComponentBuildException {
  /// Creates the error for the leaf [componentType] given [childCount]
  /// children.
  const ChildrenOnLeafException({
    required this.componentType,
    required this.childCount,
  });

  @override
  final String componentType;

  /// How many children the request carried.
  final int childCount;

  @override
  String get message =>
      'component type "$componentType" is a leaf and cannot have children '
      '(got $childCount)';
}

// ---------------------------------------------------------------------------
// Tree-shape (flat component list) errors
// ---------------------------------------------------------------------------

/// A flat keyed component list does not form a tree. Thrown by
/// `buildSeedTree` before any component is constructed.
sealed class TreeShapeException extends TaxonomyException {
  const TreeShapeException();
}

/// Two components in one list share an id.
final class DuplicateComponentIdException extends TreeShapeException {
  /// Creates the error for the duplicated [id].
  const DuplicateComponentIdException({required this.id});

  /// The id that appeared more than once.
  final String id;

  @override
  String get message =>
      'duplicate component id "$id" — component ids must be unique within '
      'one component list';
}

/// No component carries the root id.
final class UnknownRootIdException extends TreeShapeException {
  /// Creates the error for the absent [rootId], listing [knownIds].
  const UnknownRootIdException({required this.rootId, required this.knownIds});

  /// The id expected to root the tree.
  final String rootId;

  /// Every component id present, in list order.
  final List<String> knownIds;

  @override
  String get message =>
      'unknown root id "$rootId" — no component with that id; present ids: '
      '${knownIds.isEmpty ? '(none)' : knownIds.join(', ')}';
}

/// A container references a child id no component carries.
final class DanglingChildIdException extends TreeShapeException {
  /// Creates the error for [childId] referenced by [parentId].
  const DanglingChildIdException({
    required this.childId,
    required this.parentId,
  });

  /// The referenced id that resolves to nothing.
  final String childId;

  /// The id of the component whose children list referenced it.
  final String parentId;

  @override
  String get message =>
      'dangling child id "$childId" referenced by component "$parentId" — '
      'every child id must appear as a component in the same list';
}

/// The children graph contains a cycle.
final class ComponentCycleException extends TreeShapeException {
  /// Creates the error for the cycle closing at the last element of [path].
  const ComponentCycleException({required this.path});

  /// The id chain that led back to an id already on the chain; the final
  /// element is the id where the cycle closed.
  final List<String> path;

  @override
  String get message =>
      'cycle detected through component ids: ${path.join(' -> ')}';
}
