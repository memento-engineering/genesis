/// The structured result of routing an action (ADR-0005 Decision 2).
///
/// [ConsentOutcome] is a sealed union so call sites switch exhaustively (the
/// memento house style): either the action was [Applied] — enforced through
/// the target state — or it was [Rejected] with one of four kinds, each a
/// refusal of consent. A rejection is **side-effect-free**: the tree is left
/// byte-for-byte untouched, and the structured [Rejected.message] is the
/// feedback channel back to the actor (the A8 agent-async-gap loop).
library;

/// The before/after provenance of a state change an action produced
/// (ADR-0005 Decision 6 — the last-write-wins audit trail). [from] and [to]
/// are the domain's own representation of the value that changed.
final class ActionChange {
  /// Records that the value moved from [from] to [to].
  const ActionChange({required this.from, required this.to});

  /// The value before the action applied.
  final Object? from;

  /// The value after the action applied.
  final Object? to;

  @override
  String toString() => 'ActionChange($from -> $to)';
}

/// Why an action was refused (ADR-0005 Decision 2). Four kinds; the
/// load-bearing distinction is [unknownComponent] vs [staleUnmounted] — a
/// boolean rejection would erase it (the A8 feedback channel).
enum RejectionKind {
  /// The `sourceComponentId` was never part of any emission of this surface
  /// (it never existed, or it addresses a different surface).
  unknownComponent,

  /// The component existed in an earlier emission but is no longer mounted —
  /// the projection moved under the actor (ADR-0005 Decision 3, the A8
  /// async-gap bridge: consent revoked because the world changed).
  staleUnmounted,

  /// The component is mounted, but its catalog type does not declare the
  /// fired action name.
  undeclaredAction,

  /// The action is declared, but the payload (`context`) failed the target
  /// state's validation (gate 3).
  badPayload,
}

/// The result of routing one action through the enforce/reject substrate.
sealed class ConsentOutcome {
  const ConsentOutcome();
}

/// The action passed every gate and was enforced through the target state
/// (ADR-0005 Decision 4). [change] carries the before/after provenance.
final class Applied extends ConsentOutcome {
  /// Records a successful enforcement of [action] on [componentId].
  const Applied({
    required this.action,
    required this.componentId,
    required this.change,
  });

  /// The enforced action name.
  final String action;

  /// The component the action was applied to.
  final String componentId;

  /// The before/after provenance of the state change.
  final ActionChange change;

  @override
  String toString() =>
      'Applied(action: "$action", component: "$componentId", $change)';
}

/// The action was refused; the tree is byte-for-byte untouched (ADR-0005
/// Decision 2). [message] is the LLM-feedback-ready explanation.
final class Rejected extends ConsentOutcome {
  /// Records a refusal of [action] on [componentId] for [kind].
  ///
  /// [availableActions] is populated for [RejectionKind.undeclaredAction] (the
  /// component's actually-declared actions); [payloadError] for
  /// [RejectionKind.badPayload] (the target state's validation message).
  const Rejected({
    required this.kind,
    required this.action,
    required this.componentId,
    this.availableActions = const [],
    this.payloadError,
  });

  /// Which refusal this is.
  final RejectionKind kind;

  /// The refused action name.
  final String action;

  /// The component the action addressed.
  final String componentId;

  /// For [RejectionKind.undeclaredAction]: the actions the component's type
  /// *does* declare, sorted; empty for other kinds (or a type that declares
  /// none).
  final List<String> availableActions;

  /// For [RejectionKind.badPayload]: the target state's validation message;
  /// null for other kinds.
  final String? payloadError;

  /// An LLM-feedback-ready explanation, assembled from the structured fields.
  String get message => switch (kind) {
    RejectionKind.unknownComponent =>
      'action "$action" rejected (unknownComponent): no component '
          '"$componentId" has ever been part of this surface — check the '
          'sourceComponentId.',
    RejectionKind.staleUnmounted =>
      'action "$action" rejected (staleUnmounted): component "$componentId" '
          'existed in an earlier emission but is no longer mounted. The '
          'projection moved under you — re-read the current surface before '
          'acting.',
    RejectionKind.undeclaredAction =>
      'action "$action" rejected (undeclaredAction): component "$componentId" '
          'is mounted but its type does not afford "$action". Declared '
          'actions: '
          '${availableActions.isEmpty ? '(none)' : availableActions.map((a) => '"$a"').join(', ')}.',
    RejectionKind.badPayload =>
      'action "$action" rejected (badPayload): the payload for component '
          '"$componentId" is invalid${payloadError == null ? '' : ' — $payloadError'}.',
  };

  @override
  String toString() => 'Rejected($message)';
}
