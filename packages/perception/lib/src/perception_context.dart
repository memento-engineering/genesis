import 'package:meta/meta.dart';
import 'package:genesis_tree/genesis_tree.dart';

/// Capability extension of [BuildContext] for the perception domain.
///
/// The domain layers its capabilities onto the separate handle — exactly what
/// the separate-handle design is for. A `PerceptionContext` is never
/// the mounted element itself; like its [BuildContext] base, every member
/// except [mounted] throws [StateError] once the bound element unmounts, so a
/// handle held across an async gap fails loudly instead of acting on a stale
/// node.
///
/// Today this interface adds the harvest vocabulary ([markNeedsHarvest],
/// [perceptionId]). It is deliberately the seam where the perception-owned
/// **token budget** capability lands later (budget == constraints, the
/// render-tree concern that belongs to the measurement domain, never to the
/// tree spine).
abstract class PerceptionContext implements BuildContext {
  /// Domain alias of [BuildContext.elementId]: the stable id of the bound
  /// element, issued at mount.
  ///
  /// Throws [StateError] after the bound element unmounts.
  String get perceptionId;

  /// Domain alias of [BuildContext.markNeedsRebuild]: marks the bound element
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
PerceptionContext createPerceptionContext(BuildContext inner) =>
    _PerceptionHandle(inner);

/// The private domain handle (the layered capability handle): delegates every
/// [BuildContext] member to the wrapped tree handle — inheriting its
/// throw-after-unmount protection — and maps the harvest vocabulary onto it.
class _PerceptionHandle implements PerceptionContext {
  _PerceptionHandle(this._inner);

  final BuildContext _inner;

  @override
  bool get mounted => _inner.mounted;

  @override
  Key? get key => _inner.key;

  @override
  String get elementId => _inner.elementId;

  @override
  String get branchId => elementId;

  @override
  String get perceptionId => _inner.elementId;

  @override
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect}) =>
      _inner.dependOnInheritedValueOfExactType<T>(aspect: aspect);

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>({Object? aspect}) =>
      dependOnInheritedValueOfExactType<T>(aspect: aspect);

  @override
  T? getInheritedValueOfExactType<T extends Object>() =>
      _inner.getInheritedValueOfExactType<T>();

  @override
  T? getInheritedSeedOfExactType<T extends Object>() =>
      getInheritedValueOfExactType<T>();

  @override
  void markNeedsRebuild() => _inner.markNeedsRebuild();

  @override
  void markNeedsHarvest() => _inner.markNeedsRebuild();
}
