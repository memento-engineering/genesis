// Shared test fixtures for the tree package.
//
// `Node`/`NodeElement` is the bare keyed-multichild container analog of
// perception's Node, kept as a TEST FIXTURE deliberately: `tree` core is
// artifact-agnostic (ADR-0001 Decision 3), so container primitives with
// domain meaning live with their domains. Tests use this analog to exercise
// keyed reconciliation and to prove non-component elements keep their own
// artifact response (ADR-0001 Decision 4).
import 'package:genesis_tree/genesis_tree.dart';

/// Bare leaf component: its element has no children and no build contract.
class Leaf extends Component {
  const Leaf(this.tag, {super.key});
  final String tag;
  @override
  LeafElement createElement() => LeafElement(this);
}

/// Element for [Leaf]; the empty default [Element.performRebuild] hook.
class LeafElement extends Element {
  LeafElement(Leaf super.component);
}

/// Bare keyed-multichild container component (perception Node analog).
class Node extends Component {
  const Node(this.name, {this.children = const [], super.key});
  final String name;
  final List<Component> children;
  @override
  NodeElement createElement() => NodeElement(this);
}

/// Element for [Node]: a NON-component element whose artifact response in the
/// rebuild hook is keyed reconciliation of its children — no build contract.
class NodeElement extends Element {
  NodeElement(Node super.component);

  List<Element> _children = const [];

  /// Exposed for testing.
  List<Element> get children => _children;

  Node get _node => component as Node;

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, _node.children);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
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
