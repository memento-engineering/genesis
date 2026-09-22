/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'buildable_element.dart';
import 'component.dart';
import 'build_context.dart';

/// A [Component] that composes purely from its own configuration — the
/// StatelessWidget analogue.
abstract class StatelessComponent extends Component {
  /// Creates a stateless component, optionally [key]ed.
  const StatelessComponent({super.key});

  /// Describes the child subtree for this configuration. [context] is the
  /// element's capability handle, never the element itself.
  Component build(BuildContext context);

  @override
  StatelessElement createElement() => StatelessElement(this);

  @override
  @Deprecated('Use createElement instead.')
  StatelessElement createBranch() => createElement();
}

/// Mounted element for a [StatelessComponent].
class StatelessElement extends BuildableElement {
  /// Creates the element for [component].
  StatelessElement(StatelessComponent super.component);

  @override
  Component build(BuildContext context) =>
      (component as StatelessComponent).build(context);
}

/// Legacy name for [StatelessComponent].
@Deprecated('Use StatelessComponent instead.')
typedef StatelessSeed = StatelessComponent;

/// Legacy name for [StatelessElement].
@Deprecated('Use StatelessElement instead.')
typedef StatelessBranch = StatelessElement;
