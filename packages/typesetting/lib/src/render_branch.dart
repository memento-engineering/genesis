import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

import 'cell.dart';
import 'cell_grid.dart';
import 'rect.dart';
import 'stage.dart';

/// The typesetting-side render-parent protocol (register A23).
///
/// A render container provides one canonical link instance to its child
/// subtrees (via [RenderBranch.renderScopeFor]); a mounting render branch
/// finds the nearest link with the tree's public ancestor walk
/// (`dependOnInheritedSeedOfExactType<RenderParentLink>()`) and attaches to
/// `link.branch` — typesetting's analog of Flutter's
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
/// `Branch` exposes no parent pointer (and `ComponentBranch` does not thread
/// slots), so the climb is realized with the one public ancestor walk the
/// tree ships — the inherited-value lookup. Watch/Stateless/Inherited
/// wrappers (and perception's `Node`) between two render branches compose
/// transparently, exactly as component widgets do between
/// `RenderObjectWidget`s.
///
/// Links are compared by identity and are stable for the lifetime of their
/// branch, so re-providing the same link on every rebuild never notifies
/// dependents (`InheritedSeed.updateShouldNotify` sees an identical value).
class RenderParentLink {
  RenderParentLink._(this.branch);

  /// The render branch that provided this link — the enclosing render parent
  /// for every render branch mounted inside its scope.
  final RenderBranch branch;
}

/// A [Seed] whose branch bears render artifacts — the RenderObjectWidget
/// analog (register A23). Mounting one produces a [RenderBranch].
abstract class RenderSeed extends Seed {
  /// Creates a render seed, optionally [key]ed.
  const RenderSeed({super.key});

  @override
  RenderBranch createBranch();
}

/// A mounted branch that owns geometry ([rect]) and paints cells — the
/// RenderObjectElement+RenderObject analog, collapsed into one type because
/// the cell grid needs no separate retained render node (register A23;
/// ADR-0001 Decision 3's "non-component branches define their own artifact
/// response", taken literally).
///
/// The artifact response in the rebuild hook is paint: [performRebuild]
/// marks this branch needing paint, and the stage's frame pass paints it in
/// the same pass — mirroring Flutter, where `RenderObjectElement.update` →
/// `RenderObject.markNeedsPaint()` → `owner!._nodesNeedingPaint.add(this)`
/// and `PipelineOwner.flushPaint()` paints the drained dirty list within the
/// same frame.
///
/// Render-tree threading is typesetting's own (`RenderObject.parent` analog):
/// [renderParent] is linked at mount via [RenderParentLink], across any
/// intervening component branches; [renderChildren] is the downward
/// adjacency, derived from the live tree in tree order.
///
/// Layout v1 is minimal flow (register A23): the parent assigns [rect]
/// top-down via [layout]; a child reports the rows it occupies via
/// [flowHeight]. A constraints-down/sizes-up protocol is explicitly
/// DEFERRED — this is placement, not negotiation.
abstract class RenderBranch extends Branch {
  /// Creates a render branch configured by [seed].
  RenderBranch(RenderSeed super.seed);

  late final RenderParentLink _link = RenderParentLink._(this);

  RenderBranch? _renderParent;

  /// The enclosing render branch in the render tree, or null for the render
  /// root (the stage) — the `RenderObject.parent` analog. Linked at mount by
  /// [attachRenderParent]; cleared at unmount.
  RenderBranch? get renderParent => _renderParent;

  StageBinding? _binding;

  /// The stage binding this branch paints through — the `RenderObject.owner`
  /// (PipelineOwner) analog. Propagated parent-to-child by
  /// [adoptRenderChild]; null when this branch sits outside any stage.
  StageBinding? get binding => _binding;

  Rect _rect = Rect.zero;

  /// The cells this branch paints into, assigned by the parent during the
  /// layout pass. [Rect.zero] before the first layout.
  Rect get rect => _rect;

  /// The rows this branch occupies when stacked by its parent's flow
  /// (layout v1). NOT a constraints protocol — deferred, see the README.
  int get flowHeight;

  /// The direct children of this branch in the RENDER tree, in tree order —
  /// derived from the live branch tree by descending [visitChildren] and
  /// stopping at each nearest render branch, so intervening component
  /// branches are transparent.
  List<RenderBranch> get renderChildren {
    final out = <RenderBranch>[];
    void visit(Branch branch) {
      branch.visitChildren((child) {
        if (child is RenderBranch) {
          out.add(child);
        } else {
          visit(child);
        }
      });
    }

    visit(this);
    return out;
  }

  /// Wraps [child] in this branch's render scope, so every render branch
  /// mounting inside it (however deep under component branches) attaches to
  /// this branch. Render containers wrap each child seed they reconcile.
  ///
  /// The wrapper carries the child's key, so keyed reconciliation of wrapped
  /// children preserves branch identity exactly as it would unwrapped.
  @protected
  Seed renderScopeFor(Seed child) => InheritedSeed<RenderParentLink>(
    value: _link,
    child: child,
    key: child.key,
  );

  @override
  void mount(Branch? parent, Object? slot) {
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
    final link = dependOnInheritedSeedOfExactType<RenderParentLink>();
    link?.branch.adoptRenderChild(this);
  }

  /// Links [child] into this branch's render scope — the
  /// `RenderObject.adoptChild` analog (`child._parent = this; child.attach
  /// (_owner!); markNeedsLayout();`): sets the parent pointer, propagates
  /// the binding, and schedules relayout because the flow changed shape.
  @protected
  void adoptRenderChild(RenderBranch child) {
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
  void dropRenderChild(RenderBranch child) {
    assert(
      identical(child._renderParent, this),
      'dropRenderChild() called on a child this branch does not own.',
    );
    child._renderParent = null;
    child._binding = null;
    markNeedsLayout();
  }

  /// Attaches this branch DIRECTLY to [binding]. Only the stage branch calls
  /// this, for itself, at mount — every other render branch receives its
  /// binding from its render parent via [adoptRenderChild].
  @protected
  void attachBinding(StageBinding binding) {
    _binding = binding;
  }

  /// The artifact response (ADR-0001 Decisions 3 and 4): a rebuilt render
  /// branch repaints, and — layout v1 — re-flows, in the same frame pass.
  /// Containers override to reconcile children FIRST, then super-call.
  @override
  @mustCallSuper
  void performRebuild() {
    markNeedsLayout();
    markNeedsPaint();
  }

  /// Registers this branch with the stage's dirty-paint set — the
  /// `RenderObject.markNeedsPaint` analog. Flutter's walk to the nearest
  /// repaint boundary is unnecessary here: the cell grid is a single
  /// surface (one "layer"), so every render branch registers directly, the
  /// way Flutter's repaint boundaries do
  /// (`owner!._nodesNeedingPaint.add(this)`).
  void markNeedsPaint() => _binding?.scheduleRepaint(this);

  /// Schedules the stage-rooted flow relayout (layout v1 has no relayout
  /// boundaries — deferred with the constraints protocol).
  void markNeedsLayout() => _binding?.scheduleRelayout();

  /// Parent-assigned placement (layout v1): stores [newRect] and lays out
  /// render children via [performLayout]. A rect change marks this branch
  /// needing paint and tells the binding cells were vacated.
  void layout(Rect newRect) {
    if (newRect != _rect) {
      _rect = newRect;
      _binding?.noteRectChanged();
      markNeedsPaint();
    }
    performLayout();
  }

  /// Places this branch's render children inside [rect]. Leaves do nothing.
  @protected
  void performLayout() {}

  /// Paints this branch's OWN cells into [grid]'s back buffer, touching only
  /// cells inside [rect] (locality contract); children paint themselves.
  /// Must repaint the full rect deterministically — the double buffer dedups
  /// identical repaints to zero emitted bytes.
  void paint(CellGrid grid);

  /// Paints this branch, then its render subtree, parent-first (so container
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
