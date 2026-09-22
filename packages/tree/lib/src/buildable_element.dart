/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'build_context.dart';
import 'component.dart';
import 'element.dart';

/// A element that composes by building a single child [Component] — the
/// ComponentElement analogue. Defines the rebuild hook as re-running [build],
/// so a config update re-runs the builder.
abstract class BuildableElement extends Element {
  /// Forwards [component] to [Element].
  BuildableElement(super.component);

  Element? _child;

  /// The mounted child element built by [build]. Exposed for testing.
  /// Do not use in production code.
  Element? get child => _child;

  /// Builds the child configuration. [context] is this element's capability
  /// handle — never the element itself.
  @protected
  Component build(BuildContext context);

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    // First build is unconditional (Flutter's _firstBuild): a freshly mounted
    // BuildableElement builds its subtree immediately, so mountRoot(component)
    // produces a tree without an external markNeedsRebuild. Subsequent
    // rebuilds flow through markNeedsRebuild + BuildOwner.flush, or through
    // update().
    performRebuild();
  }

  @override
  void performRebuild() {
    _child = updateChild(_child, build(context), 0);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}

/// Legacy name for [BuildableElement].
@Deprecated('Use BuildableElement instead.')
typedef ComponentBranch = BuildableElement;
