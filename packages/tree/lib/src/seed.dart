import 'branch.dart';

/// Immutable configuration node — the Widget analogue (ADR-0001 Decision 2:
/// planted, describes what grows).
///
/// Pure Dart; zero Flutter imports.
abstract class Seed {
  /// Creates a seed, optionally [key]ed for keyed reconciliation.
  const Seed({this.key});

  /// Identity key used by keyed reconciliation ([Branch.updateChildren]).
  /// Null means positional (unkeyed) identity.
  final Object? key;

  /// Creates the mounted [Branch] for this configuration.
  Branch createBranch();

  /// Whether a mounted branch configured by [a] can be updated in place with
  /// [b]: same runtimeType and same [key].
  static bool canUpdate(Seed a, Seed b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}
