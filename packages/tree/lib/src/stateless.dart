/// EXPERIMENTAL — two-consumer rule (ADR-0001): this API freezes only after
/// perception and one expression surface both consume it.
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
  /// branch's capability handle (A8).
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
