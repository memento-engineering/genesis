import 'diagnostics_property.dart';

/// An object that describes its diagnostic properties.
mixin Diagnosticable {
  /// Adds this object's diagnostic properties to [properties].
  void debugFillProperties(List<DiagnosticsProperty> properties) {}

  /// Returns a deterministic multiline description of this object.
  String toStringDeep() {
    final buffer = StringBuffer();
    _writeDiagnosticable(buffer, this, 0);
    return buffer.toString();
  }
}

/// A [Diagnosticable] that also describes an ordered child tree.
mixin DiagnosticableTree on Diagnosticable {
  /// Returns this object's diagnostic children in display order.
  List<Diagnosticable> debugDescribeChildren() => const <Diagnosticable>[];
}

void _writeDiagnosticable(
  StringBuffer buffer,
  Diagnosticable value,
  int depth,
) {
  final indent = '  ' * depth;
  buffer.writeln('$indent${value.runtimeType}');
  final properties = <DiagnosticsProperty>[];
  value.debugFillProperties(properties);
  for (final property in properties) {
    buffer.writeln(
      '$indent  ${property.name}: ${_propertyValue(property)} '
      '(${property.level.name})',
    );
  }
  if (value is DiagnosticableTree) {
    for (final child in value.debugDescribeChildren()) {
      _writeDiagnosticable(buffer, child, depth + 1);
    }
  }
}

String _propertyValue(DiagnosticsProperty property) => switch (property) {
  DiagnosticsStringProperty(:final value) => value,
  DiagnosticsIntProperty(:final value) => value.toString(),
  DiagnosticsDoubleProperty(:final value) => value.toString(),
  DiagnosticsFlagProperty(:final value) => value.toString(),
  DiagnosticsEnumProperty(:final value, :final enumType) => '$enumType.$value',
  DiagnosticsDurationProperty(:final value) => value.toString(),
  DiagnosticsTimestampProperty(:final value) => value.toUtc().toIso8601String(),
  DiagnosticsReferenceProperty(:final value, :final referenceKind) =>
    '${referenceKind.name}:$value',
  DiagnosticsObjectProperty(:final properties) =>
    '{${properties.map((item) => '${item.name}: ${_propertyValue(item)}').join(', ')}}',
};
