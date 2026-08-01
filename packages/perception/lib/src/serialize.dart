/// Harvest a mounted perception fragment into plain or typed diagnostics data.
library;

// Direct dependency: the projector consumes the foundation wire contract.
// ignore: unnecessary_import
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'field.dart';
import 'node.dart';
import 'perception_element.dart';

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
    root: _snapshotNode(node),
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

TreeNode _snapshotNode(PerceptionElement element) {
  final described = DiagnosticsBuilder();
  element.debugFillProperties(described);

  String? seedType;
  String? id;
  String? key;
  final properties = <DiagnosticsProperty>[];

  for (final property in described.properties) {
    switch (property) {
      case DiagnosticsStringProperty(name: 'seedType', :final value):
        seedType = value;
      case DiagnosticsStringProperty(name: 'branchId', :final value):
        id = value;
      case DiagnosticsStringProperty(name: 'key', :final value):
        key = value;
      case DiagnosticsFlagProperty(name: 'mounted' || 'dirty'):
        break;
      default:
        properties.add(property);
    }
  }

  final children = <TreeNode>[];
  for (final child in element.debugDescribeChildren()) {
    if (child is PerceptionElement) {
      children.add(_snapshotNode(child));
    }
  }

  return TreeNode(
    seedType: seedType ?? element.seed.runtimeType.toString(),
    id: id ?? element.branchId,
    key: key,
    properties: properties,
    children: children,
  );
}
