/// Harvest a mounted perception fragment into a plain JSON map.
///
/// The measurement-to-wire step: a mounted `Node`/`Field` subtree becomes a
/// nested map a consumer can serialize or diff. A `Field` becomes
/// `name: value`; a child `Node` becomes `name: { … }`. Sibling names are the
/// map keys, so a domain that wants distinct keys gives its sibling nodes
/// distinct names.
library;

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
