/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'branch.dart';
import 'seed.dart';
import 'tree_context.dart';

/// A branch that composes by building a single child [Seed] — the
/// ComponentElement analogue. Defines the rebuild hook as re-running [build],
/// so a config update re-runs the builder.
abstract class ComponentBranch extends Branch {
  /// Forwards [seed] to [Branch].
  ComponentBranch(super.seed);

  Branch? _child;

  /// The mounted child branch built by [build]. Exposed for testing.
  /// Do not use in production code.
  Branch? get child => _child;

  /// Builds the child configuration. [context] is this branch's capability
  /// handle — never the branch itself.
  @protected
  Seed build(TreeContext context);

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    // First build is unconditional (Flutter's _firstBuild): a freshly mounted
    // ComponentBranch builds its subtree immediately, so mountRoot(seed)
    // produces a tree without an external markNeedsRebuild. Subsequent
    // rebuilds flow through markNeedsRebuild + TreeOwner.flush, or through
    // update().
    performRebuild();
  }

  @override
  void performRebuild() {
    _child = updateChild(_child, build(context), 0);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}
