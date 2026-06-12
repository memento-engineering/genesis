import 'package:genesis_tree/genesis_tree.dart';

import 'perception.dart';
import 'perception_element.dart';

/// Named container perception: a keyed-multichild structural node in a
/// measurement (lenny ADR 0001 vocabulary, ported to the tree spine).
///
/// Children are typed [Seed] (A12: perception's public signatures surface
/// tree types), so a Node freely mixes domain artifacts ([Perception]s such
/// as `Field`) with composition configs (`StatelessPerception`, `Watch`, …).
class Node extends Perception {
  /// Creates a named container with [children], optionally [key]ed.
  const Node(this.name, {this.children = const [], super.key});

  /// The structural name of this node in the measurement.
  final String name;

  /// The child configurations, reconciled by key identity.
  final List<Seed> children;

  @override
  NodeElement createElement() => NodeElement(this);
}

/// Mounted element for [Node]: a NON-component element whose artifact
/// response in the rebuild hook is keyed reconciliation of its children
/// (ADR-0001 Decisions 3 and 4) — no build contract.
class NodeElement extends PerceptionElement {
  /// Creates the element for [seed].
  NodeElement(Node super.seed);

  List<Branch> _children = const [];

  /// The mounted child branches, in tree order. Exposed for testing.
  /// Do not use in production code.
  List<Branch> get children => _children;

  Node get _node => perception as Node;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  /// The artifact response (ADR-0001 Decision 4): reconcile the children
  /// against the current configuration. A config update reaches this hook
  /// automatically (A9), so children reconcile on every in-place update.
  @override
  void performRebuild() {
    _children = updateChildren(_children, _node.children);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  void unmount() {
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}
