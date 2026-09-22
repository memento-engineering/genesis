import 'package:genesis_tree/genesis_tree.dart';

import 'perception_context.dart';

/// A configuration that composes purely from itself — the perception-domain
/// face of the tree composition layer's [StatelessComponent].
///
/// Composition is tree-owned: this class inherits the build-driven rebuild
/// hook from `BuildableElement` via [StatelessElement] and only upgrades the
/// build handle to [PerceptionContext].
abstract class StatelessPerception extends StatelessComponent {
  /// Creates a stateless perception, optionally [key]ed.
  const StatelessPerception({super.key});

  /// Describes the child subtree for this configuration. [context] is the
  /// element's [PerceptionContext] capability handle — never the element
  /// itself.
  @override
  Component build(covariant PerceptionContext context);

  @override
  StatelessPerceptionElement createElement() =>
      StatelessPerceptionElement(this);
}

/// Mounted element for [StatelessPerception]: tree's [StatelessElement] with
/// the capability handle upgraded to [PerceptionContext], so `build()`
/// receives the domain handle.
class StatelessPerceptionElement extends StatelessElement {
  /// Creates the element for [component].
  StatelessPerceptionElement(StatelessPerception super.component);

  PerceptionContext? _handle;

  @override
  PerceptionContext get context =>
      _handle ??= createPerceptionContext(super.context);
}
