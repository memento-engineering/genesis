// Shared test fixtures for the tree package.
//
// `Node`/`NodeBranch` is the bare keyed-multichild container analog of
// perception's Node, kept as a TEST FIXTURE deliberately: `tree` core is
// artifact-agnostic (ADR-0001 Decision 3), so container primitives with
// domain meaning live with their domains. Tests use this analog to exercise
// keyed reconciliation and to prove non-component branches keep their own
// artifact response (ADR-0001 Decision 4).
import 'package:genesis_tree/genesis_tree.dart';

/// Bare leaf seed: its branch has no children and no build contract.
class Leaf extends Seed {
  const Leaf(this.tag, {super.key});
  final String tag;
  @override
  LeafBranch createBranch() => LeafBranch(this);
}

/// Branch for [Leaf]; the empty default [Branch.performRebuild] hook.
class LeafBranch extends Branch {
  LeafBranch(Leaf super.seed);
}

/// Bare keyed-multichild container seed (perception Node analog).
class Node extends Seed {
  const Node(this.name, {this.children = const [], super.key});
  final String name;
  final List<Seed> children;
  @override
  NodeBranch createBranch() => NodeBranch(this);
}

/// Branch for [Node]: a NON-component branch whose artifact response in the
/// rebuild hook is keyed reconciliation of its children — no build contract.
class NodeBranch extends Branch {
  NodeBranch(Node super.seed);

  List<Branch> _children = const [];

  /// Exposed for testing.
  List<Branch> get children => _children;

  Node get _node => seed as Node;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

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
