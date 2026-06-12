import 'package:tree/tree.dart';

import 'perception_context.dart';

/// A configuration that composes purely from itself — the perception-domain
/// face of the tree composition layer's [StatelessSeed] (genesis ADR-0001
/// Decisions 3 and 6).
///
/// Composition is tree-owned: this class inherits the build-driven rebuild
/// hook from `ComponentBranch` via [StatelessBranch] and only upgrades the
/// build handle to [PerceptionContext].
abstract class StatelessPerception extends StatelessSeed {
  /// Creates a stateless perception, optionally [key]ed.
  const StatelessPerception({super.key});

  /// Describes the child subtree for this configuration. [context] is the
  /// element's [PerceptionContext] capability handle (A8/A12) — never the
  /// element itself.
  @override
  Seed build(covariant PerceptionContext context);

  @override
  StatelessPerceptionElement createBranch() => StatelessPerceptionElement(this);
}

/// Mounted element for [StatelessPerception]: tree's [StatelessBranch] with
/// the capability handle upgraded to [PerceptionContext], so `build()`
/// receives the domain handle.
class StatelessPerceptionElement extends StatelessBranch {
  /// Creates the element for [seed].
  StatelessPerceptionElement(StatelessPerception super.seed);

  PerceptionContext? _handle;

  @override
  PerceptionContext get context =>
      _handle ??= createPerceptionContext(super.context);
}
