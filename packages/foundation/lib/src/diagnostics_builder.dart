import 'diagnostics_property.dart';

/// Collects properties supplied by a diagnostic hook.
final class DiagnosticsBuilder {
  /// Creates an empty diagnostics builder.
  DiagnosticsBuilder();

  final List<DiagnosticsProperty> _properties = <DiagnosticsProperty>[];

  /// Adds [property] in display order.
  void add(DiagnosticsProperty property) => _properties.add(property);

  /// An immutable point-in-time snapshot of the collected properties.
  List<DiagnosticsProperty> get properties =>
      List<DiagnosticsProperty>.unmodifiable(_properties);
}
