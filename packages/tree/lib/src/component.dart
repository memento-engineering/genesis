import 'package:genesis_foundation/genesis_foundation.dart';

import 'element.dart';
import 'key.dart';

/// Immutable configuration for an [Element].
///
/// Pure Dart; zero Flutter imports.
abstract class Component with Diagnosticable {
  /// Creates a component, optionally [key]ed for keyed reconciliation.
  const Component({this.key});

  /// Identity [Key] used by keyed reconciliation ([Element.updateChildren]).
  /// Null means positional (unkeyed) identity.
  ///
  /// Typed as [Key] (not a bare `Object`) so the reconciliation identity
  /// carries intent and type-safety: a `ValueKey<String>` cannot silently
  /// collide with an unrelated `ValueKey<int>`, and `ObjectKey` requests
  /// identity matching explicitly. There is deliberately no `GlobalKey` — see
  /// [Key].
  final Key? key;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    properties.add(
      DiagnosticsProperty.string(
        name: 'componentType',
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

  /// Creates the mounted [Element] for this configuration.
  ///
  /// This and [createBranch] deliberately dispatch through one another so a
  /// legacy subclass overriding either spelling continues to work through
  /// both call paths. Subclasses must override one of the two methods.
  Element createElement() => createBranch();

  /// Legacy spelling for [createElement].
  @Deprecated('Use createElement instead.')
  Element createBranch() => createElement();

  /// Whether a mounted element configured by [a] can be updated in place with
  /// [b]: same runtimeType and same [key] (by [Key] equality).
  static bool canUpdate(Component a, Component b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}

/// Legacy name for [Component].
@Deprecated('Use Component instead.')
typedef Seed = Component;
