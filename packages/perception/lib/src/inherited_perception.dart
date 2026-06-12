import 'package:tree/tree.dart';

/// Provides an ambient value of type [T] to all descendants in the
/// perception tree — the perception-domain face of the tree composition
/// layer's [InheritedSeed] (genesis ADR-0001 Decisions 3 and 6).
///
/// Usage:
///   `InheritedPerception<String>(value: 'hello', child: MyNode())`
///
/// Descendants call:
///   `context.dependOnInheritedSeedOfExactType<String>()`
class InheritedPerception<T extends Object> extends InheritedSeed<T> {
  /// Creates a provider of `value` over `child`.
  const InheritedPerception({
    required super.value,
    required super.child,
    super.key,
  });

  /// Returns true when [oldPerception]'s value differs from the new value.
  /// Subclasses may override for custom equality; the parameter is covariant
  /// so domain subclasses can type it as their own configuration.
  @override
  bool updateShouldNotify(covariant InheritedPerception<T> oldPerception) =>
      super.updateShouldNotify(oldPerception);

  @override
  InheritedPerceptionElement<T> createBranch() =>
      InheritedPerceptionElement<T>(this);
}

/// Mounted element for [InheritedPerception]: tree's [InheritedBranch] —
/// dependent set, single-child reconciliation through the rebuild hook, and
/// notify-before-reconcile update ordering are all inherited.
class InheritedPerceptionElement<T extends Object> extends InheritedBranch<T> {
  /// Creates the element for [seed].
  InheritedPerceptionElement(InheritedPerception<T> super.seed);
}
