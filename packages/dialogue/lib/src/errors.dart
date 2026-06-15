/// Structured error hierarchy for genesis_dialogue.
///
/// These cover the *envelope-level* structural faults the wire layer owns:
/// a malformed `updateComponents` message or a malformed `action` message,
/// before any component is built. Deserialization faults inside the flat
/// component list (dangling child id, duplicate id, cycle, unknown
/// type/prop) belong to `genesis_taxonomy` and surface as its
/// `TaxonomyException`s — this layer does not duplicate those checks.
///
/// Every member carries structured fields and an LLM-feedback-ready
/// [message], mirroring `genesis_taxonomy`'s structured-error style so an
/// agent loop can switch exhaustively or feed the message back verbatim.
library;

/// Root of the genesis_dialogue error union.
///
/// Two sub-families, each sealed for exhaustive switching:
///
/// - [EnvelopeException] — the server→client `updateComponents` envelope is
///   malformed (the surface-emission decode channel).
/// - [ActionMessageException] — the client→server `action` message is
///   malformed (the user-action decode channel).
sealed class DialogueException implements Exception {
  const DialogueException();

  /// Human/LLM-readable description assembled from the structured fields.
  String get message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Envelope (updateComponents) errors
// ---------------------------------------------------------------------------

/// The `updateComponents` envelope is structurally malformed.
sealed class EnvelopeException extends DialogueException {
  const EnvelopeException();
}

/// The envelope carries a `version` other than the one this codec speaks.
///
/// genesis_dialogue is **strict** on version (the wire is pure A2UI v0.9):
/// the field must be present and equal to `v0.9`.
/// A missing field, or a v0.8 `version`, is rejected here rather than parsed
/// leniently — silently accepting the wrong version is how a standard rots
/// into a dialect.
final class UnsupportedVersionException extends EnvelopeException {
  /// Creates the error for the [actual] version against [expected].
  const UnsupportedVersionException({
    required this.expected,
    required this.actual,
  });

  /// The version this codec speaks (`v0.9`).
  final String expected;

  /// What the envelope actually carried (null when the field was absent).
  final Object? actual;

  @override
  String get message =>
      'unsupported A2UI version: expected "$expected", got '
      '${actual == null ? 'no "version" field' : '"$actual"'}. This codec '
      'speaks pure A2UI v0.9 (the "updateComponents" envelope); a v0.8 '
      '"surfaceUpdate" message is not accepted.';
}

/// The envelope is missing its `updateComponents` body, or the body is not an
/// object (e.g. a v0.8 `surfaceUpdate`-keyed message).
final class MissingUpdateComponentsException extends EnvelopeException {
  /// Creates the error listing the [presentKeys] of the message.
  const MissingUpdateComponentsException({required this.presentKeys});

  /// The top-level keys the message did carry, in encounter order.
  final List<String> presentKeys;

  @override
  String get message =>
      'message must carry an "updateComponents" object (A2UI v0.9 shape); '
      'present top-level keys: '
      '${presentKeys.isEmpty ? '(none)' : presentKeys.map((k) => '"$k"').join(', ')}. '
      'Note: v0.8 "surfaceUpdate" is not accepted.';
}

/// A required field of the envelope body has the wrong shape.
final class EnvelopeFieldException extends EnvelopeException {
  /// Creates a shape error at [field], stating [expected] versus [actual].
  const EnvelopeFieldException({
    required this.field,
    required this.expected,
    this.actual,
  });

  /// Dotted path of the offending field, e.g. `updateComponents.surfaceId`.
  final String field;

  /// What the envelope shape requires at [field].
  final String expected;

  /// What the message actually carried (null when absence is the error).
  final Object? actual;

  @override
  String get message =>
      'envelope error at "$field": expected $expected, got '
      '${actual == null ? 'nothing' : '$actual (${actual.runtimeType})'}';
}

/// A component object in the flat list is missing its `id` or `component`
/// discriminator, or carries them with the wrong type.
///
/// This is the *envelope-level* well-formedness of a component entry (it has
/// the two mandatory string fields). Whether the `component` type is *known*,
/// and whether the props are valid, is the registry's concern at build time.
final class MalformedComponentException extends EnvelopeException {
  /// Creates the error for the component at [index], naming the missing or
  /// mistyped [field].
  const MalformedComponentException({
    required this.index,
    required this.field,
    required this.expected,
    this.actual,
  });

  /// Zero-based position of the offending component in the `components` list.
  final int index;

  /// The offending field name (`id` or `component`).
  final String field;

  /// What the field must be.
  final String expected;

  /// What it actually was (null when absent).
  final Object? actual;

  @override
  String get message =>
      'component at index $index: "$field" must be $expected, got '
      '${actual == null ? 'nothing' : '$actual (${actual.runtimeType})'}';
}

/// Two component objects in one envelope share an `id`.
///
/// Rejected at envelope-parse time so a duplicate is reported against its
/// wire position; `buildSeedTree` would also reject it, but the envelope owns
/// the parse-time well-formedness of the list it just decoded.
final class DuplicateEnvelopeIdException extends EnvelopeException {
  /// Creates the error for the [id] first seen at [firstIndex] and repeated
  /// at [secondIndex].
  const DuplicateEnvelopeIdException({
    required this.id,
    required this.firstIndex,
    required this.secondIndex,
  });

  /// The id that appeared twice.
  final String id;

  /// Position of the first occurrence.
  final int firstIndex;

  /// Position of the repeat.
  final int secondIndex;

  @override
  String get message =>
      'duplicate component id "$id" in the envelope (first at index '
      '$firstIndex, again at index $secondIndex) — component ids must be '
      'unique within one updateComponents message';
}

// ---------------------------------------------------------------------------
// Action message errors
// ---------------------------------------------------------------------------

/// The client→server `action` message is structurally malformed.
final class ActionMessageException extends DialogueException {
  /// Creates a shape error at [field], stating [expected] versus [actual].
  const ActionMessageException({
    required this.field,
    required this.expected,
    this.actual,
  });

  /// Dotted path of the offending field, e.g. `action.sourceComponentId`.
  final String field;

  /// What the message shape requires at [field].
  final String expected;

  /// What it actually carried (null when absence is the error).
  final Object? actual;

  @override
  String get message =>
      'action message error at "$field": expected $expected, got '
      '${actual == null ? 'nothing' : '$actual (${actual.runtimeType})'}';
}
