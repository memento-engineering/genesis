/// The client→server half of the dialogue: parsing the A2UI v0.9 `action`
/// message into a typed [ActionEvent] (ADR-0003 Decision 1).
///
/// This is **parse only**. dialogue produces the typed event; it does not
/// route it, hit-test the `sourceComponentId` against the live tree, check
/// the affordance, or validate the payload against an action contract — that
/// is `genesis_consent`'s job (ADR-0005, the enforce/reject substrate; the
/// next package). The seam is deliberate: dialogue owns the wire vocabulary,
/// consent owns the world-side enforcement. An [ActionEvent] crossing this
/// boundary has been *decoded*, not *authorized*.
library;

import 'errors.dart';

/// A parsed A2UI v0.9 `action` message: a user action fired by the client
/// against a component, addressed back to the agent.
///
/// Wire fields (a2uiVersion v0.9, per the a2ui.org Message Reference): `name`
/// (the action), `surfaceId`, `sourceComponentId` (the component the action
/// fired on — the back-reference that makes id hit-testing natural),
/// `timestamp` (ISO 8601 string, optional), and `context` (the payload
/// object, optional).
final class ActionEvent {
  /// Creates a parsed action event. Prefer [parseActionEvent] from the wire.
  const ActionEvent({
    required this.name,
    required this.surfaceId,
    required this.sourceComponentId,
    this.payload = const {},
    this.timestamp,
  });

  /// The action name fired (e.g. `press`, `set`).
  final String name;

  /// The surface the firing component belongs to.
  final String surfaceId;

  /// The id of the component the action fired on — the back-reference
  /// `genesis_consent` hit-tests against the live tree.
  final String sourceComponentId;

  /// The action payload (wire field `context`); empty when absent.
  final Map<String, Object?> payload;

  /// The raw ISO 8601 timestamp string, or null when absent. Carried
  /// verbatim, not parsed (`genesis_consent` decides whether it matters).
  final String? timestamp;
}

/// Parses an A2UI v0.9 `action` message into an [ActionEvent].
///
/// Accepts either the `{"action": {...}}` envelope or a bare action object
/// (the transport envelope is unverified against the spec — see the README
/// fidelity ledger). Structural rejection via [ActionMessageException]:
/// non-object message, non-string `name`/`surfaceId`/`sourceComponentId`,
/// non-object `context`, non-string `timestamp`.
///
/// Does **not** route, hit-test, or authorize: a returned [ActionEvent] is
/// decoded, not consented. Routing belongs to `genesis_consent`.
ActionEvent parseActionEvent(Object json) {
  if (json is! Map) {
    throw ActionMessageException(
      field: '',
      expected: 'a JSON object',
      actual: json,
    );
  }
  // Accept both {"action": {...}} and a bare action object.
  final outer = json.cast<String, Object?>();
  final inner = outer['action'];
  final action = inner is Map ? inner.cast<String, Object?>() : outer;

  final name = action['name'];
  if (name is! String || name.isEmpty) {
    throw ActionMessageException(
      field: 'action.name',
      expected: 'a non-empty string',
      actual: name,
    );
  }
  final surfaceId = action['surfaceId'];
  if (surfaceId is! String) {
    throw ActionMessageException(
      field: 'action.surfaceId',
      expected: 'a string',
      actual: surfaceId,
    );
  }
  final sourceComponentId = action['sourceComponentId'];
  if (sourceComponentId is! String || sourceComponentId.isEmpty) {
    throw ActionMessageException(
      field: 'action.sourceComponentId',
      expected: 'a non-empty string',
      actual: sourceComponentId,
    );
  }

  var payload = const <String, Object?>{};
  final contextRaw = action['context'];
  if (contextRaw != null) {
    if (contextRaw is! Map) {
      throw ActionMessageException(
        field: 'action.context',
        expected: 'an object (the action payload)',
        actual: contextRaw,
      );
    }
    payload = contextRaw.cast<String, Object?>();
  }

  final timestampRaw = action['timestamp'];
  if (timestampRaw != null && timestampRaw is! String) {
    throw ActionMessageException(
      field: 'action.timestamp',
      expected: 'an ISO 8601 timestamp string',
      actual: timestampRaw,
    );
  }

  return ActionEvent(
    name: name,
    surfaceId: surfaceId,
    sourceComponentId: sourceComponentId,
    payload: payload,
    timestamp: timestampRaw as String?,
  );
}
