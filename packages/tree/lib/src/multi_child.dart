/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'branch.dart';
import 'seed.dart';

/// A [Seed] that carries a fixed, ordered list of child seeds directly in its
/// configuration — the MultiChildRenderObjectWidget analogue, and the
/// multi-child sibling of the single-child component seeds
/// (`StatelessSeed`/`StatefulSeed`/`Sprout`).
///
/// A component seed *builds* one child from a `build()` method; a
/// `MultiChildSeed` instead *declares* its children up front. Its
/// [MultiChildBranch] keyed-reconciles them against the previous set on every
/// rebuild ([Branch.updateChildren]): a child matched by key (or, when unkeyed,
/// by position) keeps its branch identity across rebuilds; a child that appears
/// mounts; a child that vanishes unmounts; and the resulting child order
/// follows [children]. The identical-config fast path is inherited unchanged —
/// a child seed reused by `identical` instance prunes its subtree at reconcile
/// time.
///
/// `MultiChildSeed` is `abstract` deliberately: a seed's `runtimeType` is its
/// reconciliation tag ([Seed.canUpdate]), so a topology of distinct container
/// kinds (e.g. a Grid of Rigs of Steps) must subclass it once per kind — two
/// kinds sharing this base directly would reconcile into one another. Subclasses
/// pass their children up and may add their own typed fields:
///
/// ```dart
/// class Grid extends MultiChildSeed {
///   const Grid(List<Rig> rigs) : super(children: rigs);
/// }
/// ```
abstract class MultiChildSeed extends Seed {
  /// Creates a multi-child seed configured with [children] (default empty),
  /// optionally [key]ed for keyed reconciliation by its own parent.
  const MultiChildSeed({this.children = const [], super.key});

  /// The ordered child configurations this seed reconciles. Each may carry its
  /// own [Seed.key] for keyed identity; unkeyed children match positionally. A
  /// key must be unique among siblings (asserted in debug by
  /// [Branch.updateChildren]).
  final List<Seed> children;

  @override
  MultiChildBranch createBranch() => MultiChildBranch(this);
}

/// Mounted branch for a [MultiChildSeed]: keyed-reconciles the seed's declared
/// [MultiChildSeed.children] — the MultiChildRenderObjectElement analogue.
///
/// It carries no build contract of its own; its rebuild hook simply reconciles
/// the live child list against the seed's children through
/// [Branch.updateChildren], so a config update (the A9 rebuild rule)
/// re-reconciles in place, preserving the branch identity of every matched
/// child. Concrete and reusable across container kinds (like `StatelessBranch`
/// across stateless seeds): a domain that needs no extra behaviour reuses it
/// verbatim; one that needs an artifact response may subclass it and extend
/// [performRebuild] after `super` (the RenderObjectElement pattern).
class MultiChildBranch extends Branch {
  /// Creates the branch for [seed].
  MultiChildBranch(MultiChildSeed super.seed);

  List<Branch> _children = const [];

  /// The mounted child branches, in tree order. Exposed for testing.
  /// Do not use in production code.
  List<Branch> get children => _children;

  List<Seed> get _childSeeds => (seed as MultiChildSeed).children;

  @override
  void mount(Branch? parent, Object? slot) {
    // First reconcile is unconditional (the ComponentBranch first-build idiom):
    // a freshly mounted container builds its child subtree immediately, so
    // mountRoot(seed) yields a full tree without an external markNeedsRebuild.
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, _childSeeds);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
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
