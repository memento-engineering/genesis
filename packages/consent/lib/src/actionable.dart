/// The dispatch seam: how a live component honors a consented action.
///
/// A domain's stateful component implements [Actionable] on its `State`. The
/// router (`genesis_consent`) calls into it only after the action has already
/// cleared the exists/mounted and catalog-declared gates — so [Actionable]
/// owns exactly the two remaining steps delegated to the target state:
///
/// - [validateAction] — gate 3, payload validation. **Pure**: it must inspect
///   the payload and throw [ActionPayloadException] on a violation without
///   mutating anything. Keeping it side-effect-free is what lets a `badPayload`
///   rejection leave the tree byte-for-byte untouched by
///   construction, not by domain discipline.
/// - [applyAction] — enforce. Applies the (already validated) action through
///   the state's setState-analogue (`perceived()` in perception), so the
///   rebuild flows through the standard dirty/flush pipeline and exactly the
///   target subtree invalidates.
library;

import 'outcome.dart';

/// Implemented by a domain's stateful component `State` to afford client
/// actions. The router invokes these only for a mounted component
/// whose catalog type declares the action name.
abstract interface class Actionable {
  /// Validates [payload] for the catalog-declared action [name] (gate 3).
  ///
  /// Must be **pure** — throw [ActionPayloadException] on an invalid payload
  /// and mutate nothing. The router calls this before [applyAction]; a throw
  /// becomes a `badPayload` rejection that leaves the tree untouched.
  void validateAction(String name, Map<String, Object?> payload);

  /// Applies the already-validated action [name] with [payload], returning the
  /// before/after [ActionChange] provenance.
  ///
  /// Apply through the state's setState-analogue so invalidation flows through
  /// the dirty/flush pipeline and exactly the target subtree rebuilds.
  ActionChange applyAction(String name, Map<String, Object?> payload);
}

/// Thrown by [Actionable.validateAction] to reject a payload (gate 3).
///
/// The router catches it and returns a `badPayload` [Rejected] carrying
/// [message] verbatim — the LLM-feedback channel for an invalid context.
class ActionPayloadException implements Exception {
  /// Creates a payload rejection with an LLM-feedback-ready [message].
  const ActionPayloadException(this.message);

  /// Why the payload is invalid; surfaced verbatim in the rejection.
  final String message;

  @override
  String toString() => 'ActionPayloadException: $message';
}
