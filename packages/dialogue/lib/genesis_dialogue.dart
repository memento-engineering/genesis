/// The A2UI v0.9 wire format (ADR-0003): the bidirectional grammar of the
/// agent↔surface exchange.
///
/// Three pieces:
///
/// - **the codec** ([parseUpdateComponents] / [UpdateComponents.toJson]) — the
///   pure A2UI v0.9 `updateComponents` envelope, lossless both directions. The
///   serialize direction is emission of an authored surface;
/// - **the receive-side surface** ([DialogueSurface]) — deserializes a message
///   through an injected `genesis_taxonomy` registry into a `genesis_tree`
///   `Seed` tree, mounts it, and reconciles re-emissions **by key** (component
///   id → `Seed` key), so whole-tree re-emission becomes an identity-preserving
///   patch;
/// - **the action half** ([parseActionEvent] → [ActionEvent]) — parses the
///   client→server `action` message. Parse only: routing/hit-testing/consent
///   belong to `genesis_consent` (ADR-0005).
///
/// dialogue is registry-agnostic (the registry is injected) and does not
/// re-implement deserialization (`buildSeedTree` lives in `genesis_taxonomy`).
/// Reverse-emission — walking a live mounted tree back into components — is
/// out of scope; it needs a taxonomy reverse-describer that does not exist as
/// built (see README).
library;

export 'src/action_event.dart';
export 'src/envelope.dart';
export 'src/errors.dart';
export 'src/surface.dart';
