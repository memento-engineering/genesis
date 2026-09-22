import 'diagnostics_property.dart';

/// A complete versioned projection of the live diagnostics tree.
final class TreeSnapshot {
  /// Creates a full snapshot stamped at [projectedAt].
  const TreeSnapshot({
    required this.contractVersion,
    required this.projectedAt,
    required this.root,
  });

  /// Decodes a complete snapshot from its wire representation.
  factory TreeSnapshot.fromJson(Map<String, Object?> json) => TreeSnapshot(
    contractVersion: checkedJsonValue<int>(json, 'contractVersion'),
    projectedAt: checkedJsonDateTime(json, 'projectedAt'),
    root: TreeNode.fromJson(checkedJsonMap(json, 'root')),
  );

  final int contractVersion;
  final DateTime projectedAt;
  final TreeNode root;

  TreeSnapshot copyWith({
    int? contractVersion,
    DateTime? projectedAt,
    TreeNode? root,
  }) => TreeSnapshot(
    contractVersion: contractVersion ?? this.contractVersion,
    projectedAt: projectedAt ?? this.projectedAt,
    root: root ?? this.root,
  );

  Map<String, Object?> toJson() => {
    'contractVersion': contractVersion,
    'projectedAt': projectedAt.toUtc().toIso8601String(),
    'root': root.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeSnapshot &&
          contractVersion == other.contractVersion &&
          projectedAt == other.projectedAt &&
          root == other.root;

  @override
  int get hashCode => Object.hash(contractVersion, projectedAt, root);
}

/// One semantic node in a [TreeSnapshot].
final class TreeNode {
  /// Creates a diagnostics node and its complete child subtree.
  const TreeNode({
    String? componentType,
    @Deprecated('Use componentType instead.') String? seedType,
    required this.id,
    this.key,
    required this.properties,
    required this.children,
  }) : assert(componentType != null || seedType != null),
       assert(componentType == null || seedType == null),
       componentType = componentType ?? seedType ?? '';

  /// Decodes a node from its wire representation.
  factory TreeNode.fromJson(Map<String, Object?> json) => TreeNode(
    componentType: checkedJsonValue<String>(json, 'seedType'),
    id: checkedJsonValue<String>(json, 'id'),
    key: checkedJsonNullableValue<String>(json, 'key'),
    properties: checkedJsonList(json, 'properties')
        .map(
          (value) => DiagnosticsProperty.fromJson(
            checkedJsonMapValue(value, 'properties'),
          ),
        )
        .toList(),
    children: checkedJsonList(json, 'children')
        .map(
          (value) => TreeNode.fromJson(checkedJsonMapValue(value, 'children')),
        )
        .toList(),
  );

  final String componentType;

  /// Legacy source spelling for [componentType].
  @Deprecated('Use componentType instead. The JSON key remains seedType.')
  String get seedType => componentType;
  final String id;
  final String? key;
  final List<DiagnosticsProperty> properties;
  final List<TreeNode> children;

  TreeNode copyWith({
    String? componentType,
    @Deprecated('Use componentType instead.') String? seedType,
    String? id,
    Object? key = copyWithAbsent,
    List<DiagnosticsProperty>? properties,
    List<TreeNode>? children,
  }) => TreeNode(
    componentType: componentType ?? seedType ?? this.componentType,
    id: id ?? this.id,
    key: identical(key, copyWithAbsent) ? this.key : key as String?,
    properties: properties ?? this.properties,
    children: children ?? this.children,
  );

  Map<String, Object?> toJson() => {
    'seedType': componentType,
    'id': id,
    'key': key,
    'properties': properties.map((property) => property.toJson()).toList(),
    'children': children.map((child) => child.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeNode &&
          componentType == other.componentType &&
          id == other.id &&
          key == other.key &&
          listEquals(properties, other.properties) &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
    componentType,
    id,
    key,
    Object.hashAll(properties),
    Object.hashAll(children),
  );
}
