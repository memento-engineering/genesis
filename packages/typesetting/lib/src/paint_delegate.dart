import 'package:genesis_tree/genesis_tree.dart';

import 'cell_grid.dart';
import 'rect.dart';

/// A fixed rectangular region of the surface, claimed by a [PaintDelegate].
///
/// Region instances returned from [PaintDelegate.assignRegions] are
/// canonical: the typesetter compares them by identity, so
/// [PaintDelegate.regionFor] must return one of those instances (or null).
class Region {
  /// Creates a region named [id] covering [rect].
  const Region(this.id, this.rect);

  /// Delegate-chosen identity (an index, a key, a branch id — opaque to
  /// typesetting).
  final Object id;

  /// The cells this region covers.
  final Rect rect;

  @override
  String toString() => 'Region($id, $rect)';
}

/// The paint seam (ADR-0001 Decision 3 / ADR-0004 Decision 1): typesetting
/// owns the surface; domains own meaning.
///
/// The consumer implements this delegate to give branches screen semantics.
/// Typesetting itself knows no domain node types — region assignment and
/// painting both come from here. The region model is deliberately simple:
/// fixed rects assigned once at mount; full layout is explicitly future work
/// (ADR-0004 backlog).
abstract class PaintDelegate {
  /// Allows const subclass constructors.
  const PaintDelegate();

  /// Called once when the typesetter mounts the tree: walk [root] (via
  /// [Branch.visitChildren], recursing as needed), claim fixed regions, and
  /// return them. The returned instances are canonical for the lifetime of
  /// the typesetter.
  List<Region> assignRegions(Branch root);

  /// Maps one rebuilt branch from the drained flush list
  /// ([TreeOwner.flush]'s return, ADR-0001 Decision 5) to the region whose
  /// content it affects, or null when it affects no painted region.
  Region? regionFor(Branch rebuilt);

  /// Repaints [region]'s current content into [grid]'s back buffer.
  ///
  /// The contract is to touch only cells inside `region.rect` (the grid
  /// clips at its own edges, but staying inside the region is what makes
  /// repaint locality hold). The double buffer dedups identical repaints, so
  /// repainting an unchanged region costs zero emitted bytes.
  void paint(CellGrid grid, Region region);
}

/// Whether [target] is [root] itself or a transitive child of it — a
/// recursive descent over [Branch.visitChildren], the ancestry helper for
/// delegates that map rebuilt branches to the subtree (and so the region)
/// containing them.
bool subtreeContains(Branch root, Branch target) {
  if (identical(root, target)) return true;
  var found = false;
  root.visitChildren((child) {
    found = found || subtreeContains(child, target);
  });
  return found;
}
