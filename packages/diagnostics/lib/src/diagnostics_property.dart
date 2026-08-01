/// Display severity attached to every diagnostics property.
enum DiagnosticsLevel { fine, info, warning, error }

/// Link target classifier for a [DiagnosticsProperty.reference].
enum ReferenceKind { bead, session, substation, pid }

/// A loud failure while decoding the diagnostics wire contract.
final class CheckedFromJsonException implements Exception {
  const CheckedFromJsonException(this.key, this.message);

  final String key;
  final String message;

  @override
  String toString() => 'CheckedFromJsonException: key "$key": $message';
}

const copyWithAbsent = Object();

bool listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

T checkedJsonValue<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw CheckedFromJsonException(key, 'expected $T, got ${value.runtimeType}');
}

T? checkedJsonNullableValue<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is T) return value as T;
  throw CheckedFromJsonException(key, 'expected $T?, got ${value.runtimeType}');
}

Map<String, Object?> checkedJsonMap(Map<String, Object?> json, String key) =>
    checkedJsonMapValue(json[key], key);

Map<String, Object?> checkedJsonMapValue(Object? value, String key) {
  if (value is Map<String, Object?>) return value;
  throw CheckedFromJsonException(
    key,
    'expected Map<String, Object?>, got ${value.runtimeType}',
  );
}

List<Object?> checkedJsonList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) return value;
  throw CheckedFromJsonException(
    key,
    'expected List, got ${value.runtimeType}',
  );
}

DateTime checkedJsonDateTime(Map<String, Object?> json, String key) {
  final value = checkedJsonValue<String>(json, key);
  try {
    return DateTime.parse(value);
  } on FormatException catch (error) {
    throw CheckedFromJsonException(key, error.message);
  }
}

T checkedEnum<T extends Enum>(List<T> values, String wireValue, String key) {
  for (final value in values) {
    if (value.name == wireValue) return value;
  }
  throw CheckedFromJsonException(key, 'unknown $T value "$wireValue"');
}

/// One typed, severity-bearing property on a diagnostics tree node.
sealed class DiagnosticsProperty {
  const DiagnosticsProperty();

  const factory DiagnosticsProperty.string({
    required String name,
    required DiagnosticsLevel level,
    required String value,
  }) = DiagnosticsStringProperty;
  const factory DiagnosticsProperty.int({
    required String name,
    required DiagnosticsLevel level,
    required int value,
  }) = DiagnosticsIntProperty;
  const factory DiagnosticsProperty.double({
    required String name,
    required DiagnosticsLevel level,
    required double value,
  }) = DiagnosticsDoubleProperty;
  const factory DiagnosticsProperty.flag({
    required String name,
    required DiagnosticsLevel level,
    required bool value,
  }) = DiagnosticsFlagProperty;
  const factory DiagnosticsProperty.enumValue({
    required String name,
    required DiagnosticsLevel level,
    required String value,
    required String enumType,
  }) = DiagnosticsEnumProperty;
  const factory DiagnosticsProperty.duration({
    required String name,
    required DiagnosticsLevel level,
    required Duration value,
  }) = DiagnosticsDurationProperty;
  const factory DiagnosticsProperty.timestamp({
    required String name,
    required DiagnosticsLevel level,
    required DateTime value,
  }) = DiagnosticsTimestampProperty;
  const factory DiagnosticsProperty.reference({
    required String name,
    required DiagnosticsLevel level,
    required ReferenceKind referenceKind,
    required String value,
  }) = DiagnosticsReferenceProperty;
  const factory DiagnosticsProperty.object({
    required String name,
    required DiagnosticsLevel level,
    required List<DiagnosticsProperty> properties,
  }) = DiagnosticsObjectProperty;

  factory DiagnosticsProperty.fromJson(Map<String, Object?> json) {
    final kind = checkedJsonValue<String>(json, 'kind');
    final name = checkedJsonValue<String>(json, 'name');
    final level = checkedEnum(
      DiagnosticsLevel.values,
      checkedJsonValue<String>(json, 'level'),
      'level',
    );
    return switch (kind) {
      'string' => DiagnosticsProperty.string(
        name: name,
        level: level,
        value: checkedJsonValue<String>(json, 'value'),
      ),
      'int' => DiagnosticsProperty.int(
        name: name,
        level: level,
        value: checkedJsonValue<int>(json, 'value'),
      ),
      'double' => DiagnosticsProperty.double(
        name: name,
        level: level,
        value: checkedJsonValue<num>(json, 'value').toDouble(),
      ),
      'flag' => DiagnosticsProperty.flag(
        name: name,
        level: level,
        value: checkedJsonValue<bool>(json, 'value'),
      ),
      'enumValue' => DiagnosticsProperty.enumValue(
        name: name,
        level: level,
        value: checkedJsonValue<String>(json, 'value'),
        enumType: checkedJsonValue<String>(json, 'enumType'),
      ),
      'duration' => DiagnosticsProperty.duration(
        name: name,
        level: level,
        value: Duration(microseconds: checkedJsonValue<int>(json, 'value')),
      ),
      'timestamp' => DiagnosticsProperty.timestamp(
        name: name,
        level: level,
        value: checkedJsonDateTime(json, 'value'),
      ),
      'reference' => DiagnosticsProperty.reference(
        name: name,
        level: level,
        referenceKind: checkedEnum(
          ReferenceKind.values,
          checkedJsonValue<String>(json, 'referenceKind'),
          'referenceKind',
        ),
        value: checkedJsonValue<String>(json, 'value'),
      ),
      'object' => DiagnosticsProperty.object(
        name: name,
        level: level,
        properties: checkedJsonList(json, 'properties')
            .map(
              (value) => DiagnosticsProperty.fromJson(
                checkedJsonMapValue(value, 'properties'),
              ),
            )
            .toList(),
      ),
      _ => throw CheckedFromJsonException(
        'kind',
        'unknown DiagnosticsProperty kind "$kind"',
      ),
    };
  }

  String get name;
  DiagnosticsLevel get level;
  Map<String, Object?> toJson();
}

final class DiagnosticsStringProperty extends DiagnosticsProperty {
  const DiagnosticsStringProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final String value;
  DiagnosticsStringProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    String? value,
  }) => DiagnosticsStringProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value,
    'kind': 'string',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsStringProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsIntProperty extends DiagnosticsProperty {
  const DiagnosticsIntProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final int value;
  DiagnosticsIntProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    int? value,
  }) => DiagnosticsIntProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value,
    'kind': 'int',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsIntProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsDoubleProperty extends DiagnosticsProperty {
  const DiagnosticsDoubleProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final double value;
  DiagnosticsDoubleProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    double? value,
  }) => DiagnosticsDoubleProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value,
    'kind': 'double',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsDoubleProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsFlagProperty extends DiagnosticsProperty {
  const DiagnosticsFlagProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final bool value;
  DiagnosticsFlagProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    bool? value,
  }) => DiagnosticsFlagProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value,
    'kind': 'flag',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsFlagProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsEnumProperty extends DiagnosticsProperty {
  const DiagnosticsEnumProperty({
    required this.name,
    required this.level,
    required this.value,
    required this.enumType,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final String value;
  final String enumType;
  DiagnosticsEnumProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    String? value,
    String? enumType,
  }) => DiagnosticsEnumProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
    enumType: enumType ?? this.enumType,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value,
    'enumType': enumType,
    'kind': 'enumValue',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsEnumProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value &&
          enumType == other.enumType;
  @override
  int get hashCode => Object.hash(name, level, value, enumType);
}

final class DiagnosticsDurationProperty extends DiagnosticsProperty {
  const DiagnosticsDurationProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final Duration value;
  DiagnosticsDurationProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    Duration? value,
  }) => DiagnosticsDurationProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value.inMicroseconds,
    'kind': 'duration',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsDurationProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsTimestampProperty extends DiagnosticsProperty {
  const DiagnosticsTimestampProperty({
    required this.name,
    required this.level,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final DateTime value;
  DiagnosticsTimestampProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    DateTime? value,
  }) => DiagnosticsTimestampProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'value': value.toUtc().toIso8601String(),
    'kind': 'timestamp',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsTimestampProperty &&
          name == other.name &&
          level == other.level &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, value);
}

final class DiagnosticsReferenceProperty extends DiagnosticsProperty {
  const DiagnosticsReferenceProperty({
    required this.name,
    required this.level,
    required this.referenceKind,
    required this.value,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final ReferenceKind referenceKind;
  final String value;
  DiagnosticsReferenceProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    ReferenceKind? referenceKind,
    String? value,
  }) => DiagnosticsReferenceProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    referenceKind: referenceKind ?? this.referenceKind,
    value: value ?? this.value,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'referenceKind': referenceKind.name,
    'value': value,
    'kind': 'reference',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsReferenceProperty &&
          name == other.name &&
          level == other.level &&
          referenceKind == other.referenceKind &&
          value == other.value;
  @override
  int get hashCode => Object.hash(name, level, referenceKind, value);
}

final class DiagnosticsObjectProperty extends DiagnosticsProperty {
  const DiagnosticsObjectProperty({
    required this.name,
    required this.level,
    required this.properties,
  });
  @override
  final String name;
  @override
  final DiagnosticsLevel level;
  final List<DiagnosticsProperty> properties;
  DiagnosticsObjectProperty copyWith({
    String? name,
    DiagnosticsLevel? level,
    List<DiagnosticsProperty>? properties,
  }) => DiagnosticsObjectProperty(
    name: name ?? this.name,
    level: level ?? this.level,
    properties: properties ?? this.properties,
  );
  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'properties': properties.map((property) => property.toJson()).toList(),
    'kind': 'object',
  };
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticsObjectProperty &&
          name == other.name &&
          level == other.level &&
          listEquals(properties, other.properties);
  @override
  int get hashCode => Object.hash(name, level, Object.hashAll(properties));
}
