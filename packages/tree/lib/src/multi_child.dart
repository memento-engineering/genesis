/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'element.dart';
import 'component.dart';

/// A [Component] that carries a fixed, ordered list of child seeds directly in its
/// configuration — the MultiChildRenderObjectWidget analogue, and the
/// multi-child sibling of the single-child component seeds
/// (`StatelessComponent`/`StatefulComponent`/`HookComponent`).
///
/// A component component *builds* one child from a `build()` method; a
/// `MultiChildComponent` instead *declares* its children up front. Its
/// [MultiChildElement] keyed-reconciles them against the previous set on every
/// rebuild ([Element.updateChildren]): a child matched by key (or, when unkeyed,
/// by position) keeps its element identity across rebuilds; a child that appears
/// mounts; a child that vanishes unmounts; and the resulting child order
/// follows [children]. The identical-config fast path is inherited unchanged —
/// a child component reused by `identical` instance prunes its subtree at reconcile
/// time.
///
/// `MultiChildComponent` is `abstract` deliberately: a component's `runtimeType` is its
/// reconciliation tag ([Component.canUpdate]), so a topology of distinct container
/// kinds (e.g. a Grid of Rigs of Steps) must subclass it once per kind — two
/// kinds sharing this base directly would reconcile into one another. Subclasses
/// pass their children up and may add their own typed fields:
///
/// ```dart
/// class Grid extends MultiChildComponent {
///   const Grid(List<Rig> rigs) : super(children: rigs);
/// }
/// ```
abstract class MultiChildComponent extends Component {
  /// Creates a multi-child component configured with [children] (default empty),
  /// optionally [key]ed for keyed reconciliation by its own parent.
  const MultiChildComponent({this.children = const [], super.key});

  /// The ordered child configurations this component reconciles. Each may carry its
  /// own [Component.key] for keyed identity; unkeyed children match positionally. A
  /// key must be unique among siblings (asserted in debug by
  /// [Element.updateChildren]).
  final List<Component> children;

  @override
  MultiChildElement createElement() => MultiChildElement(this);

  @override
  @Deprecated('Use createElement instead.')
  MultiChildElement createBranch() => createElement();
}

/// Mounted element for a [MultiChildComponent]: keyed-reconciles the component's declared
/// [MultiChildComponent.children] — the MultiChildRenderObjectElement analogue.
///
/// It carries no build contract of its own; its rebuild hook simply reconciles
/// the live child list against the component's children through
/// [Element.updateChildren], so a config update re-reconciles in place,
/// preserving the element identity of every matched child. Concrete and reusable across container kinds (like `StatelessElement`
/// across stateless seeds): a domain that needs no extra behaviour reuses it
/// verbatim; one that needs an artifact response may subclass it and extend
/// [performRebuild] after `super` (the RenderObjectElement pattern).
class MultiChildElement extends Element {
  /// Creates the element for [component].
  MultiChildElement(MultiChildComponent super.component);

  List<Element> _children = const [];

  /// The mounted child elements, in tree order. Exposed for testing.
  /// Do not use in production code.
  List<Element> get children => _children;

  List<Component> get _childComponents =>
      (component as MultiChildComponent).children;

  @override
  void mount(Element? parent, Object? slot) {
    // First reconcile is unconditional (the BuildableElement first-build idiom):
    // a freshly mounted container builds its child subtree immediately, so
    // mountRoot(component) yields a full tree without an external markNeedsRebuild.
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, _childComponents);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  void unmount() {
    // Reconcile against the empty list to unmount every child, then detach.
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}

/// Legacy name for [MultiChildComponent].
@Deprecated('Use MultiChildComponent instead.')
typedef MultiChildSeed = MultiChildComponent;

/// Legacy name for [MultiChildElement].
@Deprecated('Use MultiChildElement instead.')
typedef MultiChildBranch = MultiChildElement;
