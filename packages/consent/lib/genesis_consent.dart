/// The enforce/reject action substrate: action validation IS
/// hit-testing the live tree.
///
/// `genesis_consent` is the world-side end of the agent↔surface dialogue.
/// `genesis_dialogue` *decodes* a client `action` message into an
/// [ActionEvent] (parse only); consent *routes* it:
///
/// - **[ConsentRouter]** hit-tests the event against the live `Seed`/`Branch`
///   tree (walked fresh per call, never cached) and the catalog-declared
///   affordances, in three gates: exists/mounted, catalog-declared, payload.
/// - A valid intent is **enforced** through the target state's [Actionable]
///   seam, so the rebuild flows through the standard dirty/flush pipeline and
///   exactly the target subtree invalidates.
/// - An invalid intent is **refused** with a structured, side-effect-free
///   [ConsentOutcome]: one of four [RejectionKind]s, the tree left byte-for-byte
///   untouched. `staleUnmounted` — consent revoked because the projection moved
///   under the actor — is the agent-async-gap case made first-class.
///
/// The moat: a2ui_core has no element tree to hit-test against
/// and no unmount lifecycle, so this enforce/reject layer is genuinely
/// genesis-native. consent depends only on genesis seams.
library;

export 'src/actionable.dart';
export 'src/outcome.dart';
export 'src/router.dart';
