/// Runtime types instantiated by generated registries.
///
/// The generated `.g.dart` file is deliberately thin: it wires catalog data
/// (type names, known props, Dart constructors, defaults) into a
/// [ComponentRegistry]; all validation machinery lives here, tested once.
/// Construction-time violations throw structured `ComponentBuildException`s,
/// never bare `StateError`.
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'errors.dart';

/// Builds one `Seed` from validated wire props, already-built children, and
/// the reconciliation key.
typedef SeedFactoryFn =
    Seed Function(Map<String, Object?> props, List<Seed> children, Object? key);

/// One catalog type's runtime entry: shape flags plus the bound constructor.
final class RegistryEntry {
  /// Creates an entry. Generated code is the only intended caller.
  const RegistryEntry({
    required this.container,
    required this.knownProps,
    required this.build,
  });

  /// Whether the type accepts children; leaves reject them at construction.
  final bool container;

  /// Every prop the catalog declares for this type.
  final Set<String> knownProps;

  /// The bound Dart constructor (validates props via [Props] readers).
  final SeedFactoryFn build;
}

/// A typed factory registry binding one catalog's wire types to `Seed`
/// constructors, with construction-time validation.
///
/// Instances are emitted by the registry emitter as a generated `.g.dart`
/// file; consumers (the tree builder, the wire layer) take the registry as a
/// parameter and never import generated files themselves.
final class ComponentRegistry {
  /// Creates a registry. Generated code is the only intended caller.
  const ComponentRegistry({
    required this.catalogName,
    required this.catalogVersion,
    required this.entries,
  });

  /// Name of the catalog this registry was generated from.
  final String catalogName;

  /// Version of the catalog this registry was generated from.
  final String catalogVersion;

  /// Wire type name -> runtime entry.
  final Map<String, RegistryEntry> entries;

  /// Every wire type this registry can build, sorted.
  List<String> get typeNames => entries.keys.toList()..sort();

  /// Builds one component, validating against the catalog contract.
  ///
  /// Throws [UnknownComponentTypeException], [ChildrenOnLeafException],
  /// [UnknownPropException], and (via the [Props] readers inside the bound
  /// constructor) [MissingRequiredPropException], [PropTypeMismatchException],
  /// or [InvalidEnumValueException].
  Seed buildComponent(
    String type,
    Map<String, Object?> props,
    List<Seed> children,
    Object? key,
  ) {
    final entry = entries[type];
    if (entry == null) {
      throw UnknownComponentTypeException(
        componentType: type,
        knownTypes: typeNames,
      );
    }
    if (!entry.container && children.isNotEmpty) {
      throw ChildrenOnLeafException(
        componentType: type,
        childCount: children.length,
      );
    }
    for (final prop in props.keys) {
      if (!entry.knownProps.contains(prop)) {
        throw UnknownPropException(
          componentType: type,
          prop: prop,
          knownProps: entry.knownProps.toList()..sort(),
        );
      }
    }
    return entry.build(props, children, key);
  }
}

/// Typed wire-prop readers used by generated registry code.
///
/// Required readers throw [MissingRequiredPropException] when the prop is
/// absent (or explicit JSON null) and [PropTypeMismatchException] on a wire
/// type violation. `...Or` readers return the catalog default when the prop
/// is absent or null, validating it when present.
abstract final class Props {
  /// Reads required string prop [name] of component [type].
  static String string(String type, Map<String, Object?> props, String name) =>
      _string(type, name, _require(type, props, name, 'string'));

  /// Reads optional string prop [name], defaulting to [fallback].
  static String stringOr(
    String type,
    Map<String, Object?> props,
    String name,
    String fallback,
  ) {
    final value = props[name];
    return value == null ? fallback : _string(type, name, value);
  }

  /// Reads required integer prop [name] of component [type].
  static int integer(String type, Map<String, Object?> props, String name) =>
      _integer(type, name, _require(type, props, name, 'integer'));

  /// Reads optional integer prop [name], defaulting to [fallback].
  static int integerOr(
    String type,
    Map<String, Object?> props,
    String name,
    int fallback,
  ) {
    final value = props[name];
    return value == null ? fallback : _integer(type, name, value);
  }

  /// Reads required number prop [name] of component [type]. Integral JSON
  /// values are accepted and widened to double.
  static double number(String type, Map<String, Object?> props, String name) =>
      _number(type, name, _require(type, props, name, 'number'));

  /// Reads optional number prop [name], defaulting to [fallback].
  static double numberOr(
    String type,
    Map<String, Object?> props,
    String name,
    double fallback,
  ) {
    final value = props[name];
    return value == null ? fallback : _number(type, name, value);
  }

  /// Reads required boolean prop [name] of component [type].
  static bool boolean(String type, Map<String, Object?> props, String name) =>
      _boolean(type, name, _require(type, props, name, 'boolean'));

  /// Reads optional boolean prop [name], defaulting to [fallback].
  static bool booleanOr(
    String type,
    Map<String, Object?> props,
    String name,
    bool fallback,
  ) {
    final value = props[name];
    return value == null ? fallback : _boolean(type, name, value);
  }

  /// Reads required enum prop [name] of component [type], validating
  /// membership in [allowed] (catalog order).
  static String enumeration(
    String type,
    Map<String, Object?> props,
    String name,
    List<String> allowed,
  ) => _enumeration(type, name, allowed, _require(type, props, name, 'enum'));

  /// Reads optional enum prop [name], defaulting to [fallback].
  static String enumerationOr(
    String type,
    Map<String, Object?> props,
    String name,
    List<String> allowed,
    String fallback,
  ) {
    final value = props[name];
    return value == null ? fallback : _enumeration(type, name, allowed, value);
  }

  // --- internals ---

  static Object _require(
    String type,
    Map<String, Object?> props,
    String name,
    String expectedType,
  ) {
    final value = props[name];
    if (value == null) {
      throw MissingRequiredPropException(
        componentType: type,
        prop: name,
        expectedType: expectedType,
      );
    }
    return value;
  }

  static String _string(String type, String name, Object value) {
    if (value is String) return value;
    throw PropTypeMismatchException(
      componentType: type,
      prop: name,
      expectedType: 'string',
      actualValue: value,
    );
  }

  static int _integer(String type, String name, Object value) {
    if (value is int) return value;
    throw PropTypeMismatchException(
      componentType: type,
      prop: name,
      expectedType: 'integer',
      actualValue: value,
    );
  }

  static double _number(String type, String name, Object value) {
    if (value is num) return value.toDouble();
    throw PropTypeMismatchException(
      componentType: type,
      prop: name,
      expectedType: 'number',
      actualValue: value,
    );
  }

  static bool _boolean(String type, String name, Object value) {
    if (value is bool) return value;
    throw PropTypeMismatchException(
      componentType: type,
      prop: name,
      expectedType: 'boolean',
      actualValue: value,
    );
  }

  static String _enumeration(
    String type,
    String name,
    List<String> allowed,
    Object value,
  ) {
    if (value is! String) {
      throw PropTypeMismatchException(
        componentType: type,
        prop: name,
        expectedType: 'enum (string)',
        actualValue: value,
      );
    }
    if (!allowed.contains(value)) {
      throw InvalidEnumValueException(
        componentType: type,
        prop: name,
        allowedValues: allowed,
        actualValue: value,
      );
    }
    return value;
  }
}
