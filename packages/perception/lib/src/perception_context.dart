import 'package:meta/meta.dart';
import 'package:tree/tree.dart';

/// Capability extension of [TreeContext] for the perception domain
/// (genesis ADR-0001 Decision 6 / A12).
///
/// The domain layers its capabilities onto the separate handle — exactly what
/// the A8 separate-handle architecture is for. A `PerceptionContext` is never
/// the mounted element itself; like its [TreeContext] base, every member
/// except [mounted] throws [StateError] once the bound element unmounts, so a
/// handle held across an async gap fails loudly instead of acting on a stale
/// node.
///
/// Today this interface adds the harvest vocabulary ([markNeedsHarvest],
/// [perceptionId]). It is deliberately the seam where the perception-owned
/// **token budget** capability lands later (ADR-0001 Decision 3: budget ==
/// constraints, the render-tree concern that belongs to the measurement
/// domain, never to the tree spine).
abstract class PerceptionContext implements TreeContext {
  /// Domain alias of [TreeContext.branchId]: the stable id of the bound
  /// element, issued at mount.
  ///
  /// Throws [StateError] after the bound element unmounts.
  String get perceptionId;

  /// Domain alias of [TreeContext.markNeedsRebuild]: marks the bound element
  /// dirty so the next `PerceptionOwner.flushHarvest` re-runs its rebuild
  /// hook.
  ///
  /// Throws [StateError] after the bound element unmounts.
  void markNeedsHarvest();
}

/// Wraps the canonical tree handle [inner] with the perception capabilities.
///
/// Package-internal: code obtains an element's handle via its `context`
/// getter; perception's element classes use this to upgrade the tree handle.
@internal
PerceptionContext createPerceptionContext(TreeContext inner) =>
    _PerceptionHandle(inner);

/// The private domain handle (A12 handle layering): delegates every
/// [TreeContext] member to the wrapped tree handle — inheriting its A8
/// throw-after-unmount protection — and maps the harvest vocabulary onto it.
class _PerceptionHandle implements PerceptionContext {
  _PerceptionHandle(this._inner);

  final TreeContext _inner;

  @override
  bool get mounted => _inner.mounted;

  @override
  Object? get key => _inner.key;

  @override
  String get branchId => _inner.branchId;

  @override
  String get perceptionId => _inner.branchId;

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>() =>
      _inner.dependOnInheritedSeedOfExactType<T>();

  @override
  void markNeedsRebuild() => _inner.markNeedsRebuild();

  @override
  void markNeedsHarvest() => _inner.markNeedsRebuild();
}
