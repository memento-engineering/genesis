import 'package:tree/tree.dart';

import 'perception_context.dart';

/// A configuration whose element owns mutable [PerceptionState] — the
/// perception-domain face of the tree composition layer's [StatefulSeed]
/// (genesis ADR-0001 Decisions 3 and 6).
abstract class StatefulPerception extends StatefulSeed {
  /// Creates a stateful perception, optionally [key]ed.
  const StatefulPerception({super.key});

  /// Creates the mutable state for an element of this perception.
  @override
  PerceptionState<StatefulPerception> createState();

  @override
  StatefulPerceptionElement createBranch() => StatefulPerceptionElement(this);
}

/// Mutable state owned by a [StatefulPerceptionElement] — the perception
/// face of the tree composition layer's [State], with the domain vocabulary
/// layered on:
///
/// - [perception] — domain alias of [State.seed];
/// - [perceived] — domain alias of the tree setState-analogue
///   ([State.setState]);
/// - [context] — the handle, upgraded to [PerceptionContext].
abstract class PerceptionState<T extends StatefulPerception> extends State<T> {
  /// Domain alias of [State.seed]: the current [StatefulPerception]
  /// configuration of the owning element.
  T get perception => seed;

  /// The owning element's capability handle (A8), upgraded to
  /// [PerceptionContext]: a separate object, never the element itself;
  /// throws [StateError] when used after unmount (except `mounted`).
  @override
  PerceptionContext get context => super.context as PerceptionContext;

  /// Describes the child subtree for the current configuration and state.
  /// [context] is the element's [PerceptionContext] capability handle.
  @override
  Seed build(covariant PerceptionContext context);

  /// Domain alias of the tree setState-analogue ([State.setState]): applies
  /// [fn], then marks the owning element as needing harvest.
  void perceived(VoidCallback fn) => setState(fn);
}

/// Mounted element for [StatefulPerception]: tree's [StatefulBranch] with
/// the capability handle upgraded to [PerceptionContext] and the state
/// surfaced as [PerceptionState].
class StatefulPerceptionElement extends StatefulBranch {
  /// Creates the element and its [PerceptionState] for [seed].
  StatefulPerceptionElement(StatefulPerception super.seed);

  PerceptionContext? _handle;

  @override
  PerceptionContext get context =>
      _handle ??= createPerceptionContext(super.context);

  /// The state object, typed as [PerceptionState]. Exposed for testing.
  /// Do not use in production code.
  @override
  PerceptionState<StatefulPerception> get state =>
      super.state as PerceptionState<StatefulPerception>;
}
