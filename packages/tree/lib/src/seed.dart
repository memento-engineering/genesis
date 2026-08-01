import 'package:genesis_foundation/genesis_foundation.dart';

import 'branch.dart';
import 'key.dart';

/// Immutable configuration node — the Widget analogue: planted, describes
/// what grows.
///
/// Pure Dart; zero Flutter imports.
abstract class Seed with Diagnosticable {
  /// Creates a seed, optionally [key]ed for keyed reconciliation.
  const Seed({this.key});

  /// Identity [Key] used by keyed reconciliation ([Branch.updateChildren]).
  /// Null means positional (unkeyed) identity.
  ///
  /// Typed as [Key] (not a bare `Object`) so the reconciliation identity
  /// carries intent and type-safety: a `ValueKey<String>` cannot silently
  /// collide with an unrelated `ValueKey<int>`, and `ObjectKey` requests
  /// identity matching explicitly. There is deliberately no `GlobalKey` — see
  /// [Key].
  final Key? key;

  @override
  void debugFillProperties(List<DiagnosticsProperty> properties) {
    properties.add(
      DiagnosticsProperty.string(
        name: 'seedType',
        level: DiagnosticsLevel.info,
        value: runtimeType.toString(),
      ),
    );
    final key = this.key;
    if (key != null) {
      properties.add(
        DiagnosticsProperty.string(
          name: 'key',
          level: DiagnosticsLevel.info,
          value: key.toString(),
        ),
      );
    }
  }

  /// Creates the mounted [Branch] for this configuration.
  Branch createBranch();

  /// Whether a mounted branch configured by [a] can be updated in place with
  /// [b]: same runtimeType and same [key] (by [Key] equality).
  static bool canUpdate(Seed a, Seed b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}
