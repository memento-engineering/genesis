/// Harvest a mounted perception fragment into plain or typed diagnostics data.
library;

import 'package:genesis_diagnostics/genesis_diagnostics.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'field.dart';
import 'node.dart';

/// Serializes the perception subtree rooted at [root] into a JSON-able map.
///
/// A `StatelessPerception`/`StatefulPerception` root mounts as a
/// [ComponentBranch]; its built child is unwrapped first, so passing either the
/// component root or a bare `Node` root works. A root that does not resolve to
/// a [NodeElement] yields an empty map.
Map<String, Object?> serializePerceptionFragment(Branch root) {
  final node = root is ComponentBranch ? root.child : root;
  if (node is! NodeElement) return const <String, Object?>{};
  return _serializeNode(node);
}

/// Projects the perception subtree rooted at [root] to diagnostics contract 1.
///
/// The optional [projectedAt] supports deterministic capture and tests. When
/// omitted, the projection uses the current time. A component root is unwrapped
/// once; if the resolved root is not a [NodeElement], this throws
/// [ArgumentError] because [TreeSnapshot] requires a semantic root node.
TreeSnapshot projectPerceptionTree(Branch root, {DateTime? projectedAt}) {
  final node = root is ComponentBranch ? root.child : root;
  if (node is! NodeElement) {
    throw ArgumentError.value(root, 'root', 'must resolve to a NodeElement');
  }
  return TreeSnapshot(
    contractVersion: 1,
    projectedAt: (projectedAt ?? DateTime.now()).toUtc(),
    root: _projectNode(node),
  );
}

Map<String, Object?> _serializeNode(NodeElement element) {
  final result = <String, Object?>{};
  element.visitChildren((child) {
    if (child is FieldElement) {
      result[child.field.name] = child.field.value;
    } else if (child is NodeElement) {
      result[(child.perception as Node).name] = _serializeNode(child);
    }
  });
  return result;
}

TreeNode _projectNode(NodeElement element) {
  final properties = <DiagnosticsProperty>[];
  final children = <TreeNode>[];
  element.visitChildren((child) {
    if (child is FieldElement) {
      properties.add(_projectField(child.field));
    } else if (child is NodeElement) {
      children.add(_projectNode(child));
    }
  });
  return TreeNode(
    seedType: element.seed.runtimeType.toString(),
    id: element.branchId,
    key: element.key?.toString(),
    properties: properties,
    children: children,
  );
}

DiagnosticsProperty _projectField(Field field) {
  const level = DiagnosticsLevel.info;
  final value = field.value;
  if (value is String) {
    return DiagnosticsProperty.string(
      name: field.name,
      level: level,
      value: value,
    );
  }
  if (value is int) {
    return DiagnosticsProperty.int(
      name: field.name,
      level: level,
      value: value,
    );
  }
  if (value is double) {
    return DiagnosticsProperty.double(
      name: field.name,
      level: level,
      value: value,
    );
  }
  if (value is bool) {
    return DiagnosticsProperty.flag(
      name: field.name,
      level: level,
      value: value,
    );
  }
  if (value is Enum) {
    return DiagnosticsProperty.enumValue(
      name: field.name,
      level: level,
      value: value.name,
      enumType: value.runtimeType.toString(),
    );
  }
  if (value is Duration) {
    return DiagnosticsProperty.duration(
      name: field.name,
      level: level,
      value: value,
    );
  }
  if (value is DateTime) {
    return DiagnosticsProperty.timestamp(
      name: field.name,
      level: level,
      value: value,
    );
  }
  return DiagnosticsProperty.object(
    name: field.name,
    level: level,
    properties: [
      DiagnosticsProperty.string(
        name: 'value',
        level: level,
        value: value.toString(),
      ),
    ],
  );
}
