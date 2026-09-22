import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

import 'cell.dart';
import 'cell_grid.dart';
import 'rect.dart';
import 'stage.dart';

/// The typesetting-side render-parent protocol.
///
/// A render container provides one canonical link instance to its child
/// subtrees (via [RenderElement.renderScopeFor]); a mounting render element
/// finds the nearest link with the tree's public ancestor walk
/// (`dependOnInheritedValueOfExactType<RenderParentLink>()`) and attaches to
/// `link.element` — typesetting's analog of Flutter's
/// `RenderObjectElement._findAncestorRenderObjectElement()`, which climbs
/// `Element._parent` past intervening component elements:
///
/// ```dart
/// // framework.dart
/// Element? ancestor = _parent;
/// while (ancestor != null && ancestor is! RenderObjectElement) {
///   ancestor = ancestor?._parent;
/// }
/// ```
///
/// `Element` exposes no parent pointer (and `BuildableElement` does not thread
/// slots), so the climb is realized with the one public ancestor walk the
/// tree ships — the inherited-value lookup. Watch/Stateless/Inherited
/// wrappers (and perception's `Node`) between two render elements compose
/// transparently, exactly as component widgets do between
/// `RenderObjectWidget`s.
///
/// Links are compared by identity and are stable for the lifetime of their
/// element, so re-providing the same link on every rebuild never notifies
/// dependents (`InheritedComponent.updateShouldNotify` sees an identical value).
class RenderParentLink {
  RenderParentLink._(this.element);

  /// The render element that provided this link — the enclosing render parent
  /// for every render element mounted inside its scope.
  final RenderElement element;

  /// Legacy spelling for [element].
  @Deprecated('Use element instead.')
  RenderElement get branch => element;
}

/// A [Component] whose element bears render artifacts — the RenderObjectWidget
/// analog. Mounting one produces a [RenderElement].
abstract class RenderComponent extends Component {
  /// Creates a render component, optionally [key]ed.
  const RenderComponent({super.key});

  @override
  RenderElement createElement();
}

/// A mounted element that owns geometry ([rect]) and paints cells — the
/// RenderObjectElement+RenderObject analog, collapsed into one type because
/// the cell grid needs no separate retained render node (non-component
/// elements define their own artifact response, taken literally).
///
/// The artifact response in the rebuild hook is paint: [performRebuild]
/// marks this element needing paint, and the stage's frame pass paints it in
/// the same pass — mirroring Flutter, where `RenderObjectElement.update` →
/// `RenderObject.markNeedsPaint()` → `owner!._nodesNeedingPaint.add(this)`
/// and `PipelineOwner.flushPaint()` paints the drained dirty list within the
/// same frame.
///
/// Render-tree threading is typesetting's own (`RenderObject.parent` analog):
/// [renderParent] is linked at mount via [RenderParentLink], across any
/// intervening component elements; [renderChildren] is the downward
/// adjacency, derived from the live tree in tree order.
///
/// Layout v1 is minimal flow: the parent assigns [rect]
/// top-down via [layout]; a child reports the rows it occupies via
/// [flowHeight]. A constraints-down/sizes-up protocol is explicitly
/// DEFERRED — this is placement, not negotiation.
abstract class RenderElement extends Element {
  /// Creates a render element configured by [component].
  RenderElement(RenderComponent super.component);

  late final RenderParentLink _link = RenderParentLink._(this);

  RenderElement? _renderParent;

  /// The enclosing render element in the render tree, or null for the render
  /// root (the stage) — the `RenderObject.parent` analog. Linked at mount by
  /// [attachRenderParent]; cleared at unmount.
  RenderElement? get renderParent => _renderParent;

  StageBinding? _binding;

  /// The stage binding this element paints through — the `RenderObject.owner`
  /// (PipelineOwner) analog. Propagated parent-to-child by
  /// [adoptRenderChild]; null when this element sits outside any stage.
  StageBinding? get binding => _binding;

  Rect _rect = Rect.zero;

  /// The cells this element paints into, assigned by the parent during the
  /// layout pass. [Rect.zero] before the first layout.
  Rect get rect => _rect;

  /// The rows this element occupies when stacked by its parent's flow
  /// (layout v1). NOT a constraints protocol — deferred, see the README.
  int get flowHeight;

  /// The direct children of this element in the RENDER tree, in tree order —
  /// derived from the live element tree by descending [visitChildren] and
  /// stopping at each nearest render element, so intervening component
  /// elements are transparent.
  List<RenderElement> get renderChildren {
    final out = <RenderElement>[];
    void visit(Element element) {
      element.visitChildren((child) {
        if (child is RenderElement) {
          out.add(child);
        } else {
          visit(child);
        }
      });
    }

    visit(this);
    return out;
  }

  /// Wraps [child] in this element's render scope, so every render element
  /// mounting inside it (however deep under component elements) attaches to
  /// this element. Render containers wrap each child component they reconcile.
  ///
  /// A keyed child's wrapper gets a NAMESPACED key ([_RenderScopeKey]): it is
  /// stable across rebuilds, so the container's keyed reconcile keeps pairing
  /// each wrapper with its child (including across reorders), but it is
  /// DISTINCT from the child's own key — so the child stays the single element
  /// that answers to that key. Reusing the bare child key would mint a second
  /// element (this wrapper) bearing the child's key, and any key-based tree
  /// lookup — e.g. an action router resolving an A2UI component id to its
  /// element — would then find two elements for one id. An unkeyed child
  /// leaves the wrapper unkeyed (positional reconcile), unchanged.
  @protected
  Component renderScopeFor(Component child) {
    final childKey = child.key;
    return InheritedComponent<RenderParentLink>(
      value: _link,
      child: child,
      key: childKey == null ? null : _RenderScopeKey(childKey),
    );
  }

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    attachRenderParent();
    performRebuild();
  }

  /// Finds the enclosing render parent and attaches to it — the
  /// `RenderObjectElement.attachRenderObject` analog (`_ancestorRenderObject
  /// Element = _findAncestorRenderObjectElement()` + `insertRenderObject
  /// Child`). Called at mount, AFTER the tree parent is in place, so the
  /// ancestor walk sees the fully mounted chain — including the dynamic
  /// case, where a component rebuild deep in the tree replaces its render
  /// child and the replacement must re-attach without the container's help.
  @protected
  void attachRenderParent() {
    final link = dependOnInheritedValueOfExactType<RenderParentLink>();
    link?.element.adoptRenderChild(this);
  }

  /// Links [child] into this element's render scope — the
  /// `RenderObject.adoptChild` analog (`child._parent = this; child.attach
  /// (_owner!); markNeedsLayout();`): sets the parent pointer, propagates
  /// the binding, and schedules relayout because the flow changed shape.
  @protected
  void adoptRenderChild(RenderElement child) {
    assert(
      child._renderParent == null,
      'adoptRenderChild() called on a child that already has a render '
      'parent.',
    );
    child._renderParent = this;
    child._binding = _binding;
    markNeedsLayout();
  }

  /// Unlinks [child] — the `RenderObject.dropChild` analog. Called by the
  /// child's [unmount].
  @protected
  void dropRenderChild(RenderElement child) {
    assert(
      identical(child._renderParent, this),
      'dropRenderChild() called on a child this element does not own.',
    );
    child._renderParent = null;
    child._binding = null;
    markNeedsLayout();
  }

  /// Attaches this element DIRECTLY to [binding]. Only the stage element calls
  /// this, for itself, at mount — every other render element receives its
  /// binding from its render parent via [adoptRenderChild].
  @protected
  void attachBinding(StageBinding binding) {
    _binding = binding;
  }

  /// The artifact response: a rebuilt render
  /// element repaints, and — layout v1 — re-flows, in the same frame pass.
  /// Containers override to reconcile children FIRST, then super-call.
  @override
  @mustCallSuper
  void performRebuild() {
    markNeedsLayout();
    markNeedsPaint();
  }

  /// Registers this element with the stage's dirty-paint set — the
  /// `RenderObject.markNeedsPaint` analog. Flutter's walk to the nearest
  /// repaint boundary is unnecessary here: the cell grid is a single
  /// surface (one "layer"), so every render element registers directly, the
  /// way Flutter's repaint boundaries do
  /// (`owner!._nodesNeedingPaint.add(this)`).
  void markNeedsPaint() => _binding?.scheduleRepaint(this);

  /// Schedules the stage-rooted flow relayout (layout v1 has no relayout
  /// boundaries — deferred with the constraints protocol).
  void markNeedsLayout() => _binding?.scheduleRelayout();

  /// Parent-assigned placement (layout v1): stores [newRect] and lays out
  /// render children via [performLayout]. A rect change marks this element
  /// needing paint and tells the binding cells were vacated.
  void layout(Rect newRect) {
    if (newRect != _rect) {
      _rect = newRect;
      _binding?.noteRectChanged();
      markNeedsPaint();
    }
    performLayout();
  }

  /// Places this element's render children inside [rect]. Leaves do nothing.
  @protected
  void performLayout() {}

  /// Paints this element's OWN cells into [grid]'s back buffer, touching only
  /// cells inside [rect] (locality contract); children paint themselves.
  /// Must repaint the full rect deterministically — the double buffer dedups
  /// identical repaints to zero emitted bytes.
  void paint(CellGrid grid);

  /// Paints this element, then its render subtree, parent-first (so container
  /// blanking never erases child content). Called by the stage's paint pass.
  void paintSubtree(CellGrid grid) {
    paint(grid);
    for (final child in renderChildren) {
      child.paintSubtree(grid);
    }
  }

  /// Blanks every cell of [rect] in [grid] — the shared paint preamble that
  /// makes repaints deterministic (stale glyphs cannot survive a repaint).
  @protected
  void clearRect(CellGrid grid) {
    for (var y = _rect.top; y < _rect.bottom; y++) {
      for (var x = _rect.left; x < _rect.right; x++) {
        grid.set(x, y, Cell.blank);
      }
    }
  }

  @override
  void unmount() {
    _renderParent?.dropRenderChild(this);
    super.unmount();
  }
}

/// The namespaced key a render container puts on each keyed child's
/// [RenderElement.renderScopeFor] wrapper.
///
/// The wrapper must be keyed so the container's keyed reconcile pairs it with
/// its child across rebuilds and reorders, but it must not reuse the child's
/// own key (see [RenderElement.renderScopeFor]): wrapping the child key in a
/// distinct type keeps reconcile stable while preserving one-element-per-key
/// for the child itself. Compared by value so two wrappers derived from the
/// same child key are interchangeable across a rebuild.
///
/// A first-class [Key] (it extends [Key], so it slots straight into
/// `Component.key`): the spine types reconciliation identity as [Key], and this
/// namespaced wrapper is just another key kind defined by a consumer — exactly
/// the open-`Key` extension point the spine reserves for domains.
class _RenderScopeKey extends Key {
  const _RenderScopeKey(this.childKey) : super.empty();

  /// The wrapped child's [Key] this scope key is derived from.
  final Key childKey;

  @override
  bool operator ==(Object other) =>
      other is _RenderScopeKey && other.childKey == childKey;

  @override
  int get hashCode => Object.hash(_RenderScopeKey, childKey);
}

/// Legacy name for [RenderComponent].
@Deprecated('Use RenderComponent instead.')
typedef RenderSeed = RenderComponent;

/// Legacy name for [RenderElement].
@Deprecated('Use RenderElement instead.')
typedef RenderBranch = RenderElement;
