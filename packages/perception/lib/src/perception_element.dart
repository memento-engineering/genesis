import 'package:tree/tree.dart';

import 'perception.dart';
import 'perception_context.dart';

/// Mounted, live node in the perception tree — `PerceptionElement extends
/// Branch` (genesis ADR-0001 Decision 6 / A12).
///
/// Identity, lifecycle, keyed reconciliation, dirtiness, and the rebuild hook
/// are all inherited from the tree spine; this class adds the measurement
/// domain's vocabulary on top:
///
/// - [perception] — the domain view of [seed];
/// - [perceptionId] — the domain alias of [branchId];
/// - [markNeedsHarvest] — the domain alias of the tree rebuild-marking, and
///   the single domain override point: tree-core invalidation
///   ([markNeedsRebuild], e.g. provider `dependencyChanged`) funnels through
///   it, so subclasses observing harvest scheduling override one method;
/// - [context] — the A8 capability handle, upgraded to [PerceptionContext].
///
/// Per ADR-0001 Decision 2 (A8) this element deliberately does NOT implement
/// [PerceptionContext] — lenny ADR 0001's `PerceptionElement implements
/// PerceptionContext` re-committed Flutter's Element≡BuildContext sin, and
/// genesis sheds it.
abstract class PerceptionElement extends Branch {
  /// Creates an element configured by [perception].
  PerceptionElement(Perception super.seed);

  /// The current [Perception] configuration — the domain view of [seed].
  Perception get perception => seed as Perception;

  /// Domain alias of [branchId]: stable id for this mounted element,
  /// assigned at mount and never changing during the element's lifetime.
  String get perceptionId => branchId;

  PerceptionContext? _handle;

  /// The capability handle for this element (A8), upgraded with the
  /// perception capabilities (A12 handle layering). Lazily wraps the
  /// canonical tree handle once; never the element itself.
  @override
  PerceptionContext get context =>
      _handle ??= createPerceptionContext(super.context);

  /// Funnel override: tree-core invalidation routes through the domain
  /// vocabulary, so overriding [markNeedsHarvest] observes every scheduling
  /// path (direct harvest marking and provider invalidation alike).
  @override
  void markNeedsRebuild() => markNeedsHarvest();

  /// Marks this element dirty so the next `PerceptionOwner.flushHarvest`
  /// re-runs its rebuild hook — delegates to the tree rebuild-marking
  /// ([Branch.markNeedsRebuild]).
  void markNeedsHarvest() => super.markNeedsRebuild();
}
