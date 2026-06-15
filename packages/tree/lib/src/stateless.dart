/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'component_branch.dart';
import 'seed.dart';
import 'tree_context.dart';

/// A [Seed] that composes purely from its own configuration — the
/// StatelessWidget analogue.
abstract class StatelessSeed extends Seed {
  /// Creates a stateless seed, optionally [key]ed.
  const StatelessSeed({super.key});

  /// Describes the child subtree for this configuration. [context] is the
  /// branch's capability handle, never the branch itself.
  Seed build(TreeContext context);

  @override
  StatelessBranch createBranch() => StatelessBranch(this);
}

/// Mounted branch for a [StatelessSeed]: delegates [build] to the seed.
class StatelessBranch extends ComponentBranch {
  /// Creates the branch for [seed].
  StatelessBranch(StatelessSeed super.seed);

  @override
  Seed build(TreeContext context) => (seed as StatelessSeed).build(context);
}
