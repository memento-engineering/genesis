/// The enforce/reject router: action validation IS hit-testing the live tree
/// (ADR-0005 Decision 2).
///
/// `genesis_consent` is the world-side end of the dialogue that `genesis_dialogue`
/// opened: dialogue *decodes* an `action` message into an [ActionEvent] (parse
/// only); consent *routes* that event — hit-testing it against the live
/// `Seed`/`Branch` tree and the catalog-declared affordances, then either
/// enforcing it through the target state or refusing it with a structured,
/// side-effect-free [Rejected].
library;

import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'actionable.dart';
import 'outcome.dart';

/// Routes parsed A2UI actions onto a live [DialogueSurface], enforcing or
/// rejecting each by hit-testing the mounted tree (ADR-0005).
///
/// The router is the **front door** for an action-enabled surface. It owns the
/// emission bookkeeping the hit-test needs — the set of component ids ever
/// seen (to tell `unknownComponent` from `staleUnmounted`) and the current
/// id → wire-type map (to look up affordances) — which dialogue's surface does
/// not track. So drive emissions through the router's [mount]/[apply], not the
/// surface's directly; the router forwards to the surface and keeps its ledger
/// in sync. A renderer can still share the surface's [TreeOwner] for drawing.
///
/// What it consumes (the seams that already exist):
///
/// - the live [DialogueSurface] — the mounted tree to hit-test against, walked
///   *fresh on every [route] call* (no cached branch refs — the A8 rule);
/// - the parsed [Catalog] — `genesis_taxonomy`'s catalog-declared `actions`
///   (the same source of truth the LLM saw as `x-actions` in the tool schema),
///   for the affordance gate;
/// - the target state's [Actionable] seam — for payload validation (gate 3)
///   and enforcement (the `perceived()`/setState path of Decision 4).
final class ConsentRouter {
  /// Creates a router over a live [surface] and its [catalog].
  ///
  /// [catalog] must be parsed with the actions extension (the default
  /// `Catalog.parse` extensions include it) so `CatalogType.actions` is
  /// populated — that is the affordance channel the hit-test gate consults.
  ConsentRouter({required this.surface, required this.catalog});

  /// The live surface whose mounted tree this router hit-tests against.
  final DialogueSurface surface;

  /// The catalog whose per-type `actions` declarations the affordance gate
  /// checks (the same declarations projected to the LLM as `x-actions`).
  final Catalog catalog;

  /// Every component id that has appeared in any emission, accumulated across
  /// [mount]/[apply]. Distinguishes `unknownComponent` (never seen) from
  /// `staleUnmounted` (seen, since unmounted).
  final Set<String> _everSeenIds = {};

  /// Current emission's component id → wire type name. Replaced each emission;
  /// every mounted component's id is present (mounted ⟹ in the current tree).
  final Map<String, String> _typeById = {};

  /// Mounts [message] as the initial surface tree and records its emission.
  ///
  /// Forwards to [DialogueSurface.mount] and returns the mounted root branch;
  /// throws [StateError] if the surface is already mounted.
  Branch mount(UpdateComponents message) {
    final root = surface.mount(message);
    _record(message);
    return root;
  }

  /// Reconciles [message] onto the mounted tree by key and records the new
  /// emission (union into the ever-seen set; replace the current id → type
  /// map). Forwards to [DialogueSurface.apply].
  void apply(UpdateComponents message) {
    surface.apply(message);
    _record(message);
  }

  /// The mounted root branch, or null before [mount].
  Branch? get rootBranch => surface.rootBranch;

  /// The current surface id, or null before [mount].
  String? get surfaceId => surface.surfaceId;

  void _record(UpdateComponents message) {
    _typeById.clear();
    for (final component in message.components) {
      _typeById[component.id] = component.type;
      _everSeenIds.add(component.id);
    }
  }

  /// Routes [event] against the live tree, returning the structured outcome
  /// (ADR-0005 Decision 2). Never mutates the tree on a [Rejected] path.
  ///
  /// Three catalog/tree-derived gates, none hardcoded:
  ///
  /// 1. **exists/mounted** — `sourceComponentId` resolves to a mounted branch
  ///    by walking the live tree fresh; otherwise `staleUnmounted` (ever-seen)
  ///    or `unknownComponent` (never seen);
  /// 2. **catalog-declared** — the live component's wire type declares the
  ///    action name in [catalog]; otherwise `undeclaredAction`;
  /// 3. **payload** — the target state validates `context`; a throw is
  ///    `badPayload`.
  ///
  /// A valid intent is enforced via the target state's [Actionable.applyAction]
  /// (Decision 4) and returned as [Applied] with the change provenance.
  ///
  /// Throws [StateError] for developer/authoring errors (never actor feedback):
  /// called before [mount]; [ActionEvent.sourceComponentId] resolving to more
  /// than one mounted branch (a DAG-shared id); or a mounted component whose
  /// catalog type declares the action but whose branch/state does not implement
  /// [Actionable].
  ConsentOutcome route(ActionEvent event) {
    final root = surface.rootBranch;
    if (root == null) {
      throw StateError(
        'ConsentRouter.route called before mount(); mount a surface first',
      );
    }

    // Gate 1a — surface scoping. Single-surface v1: an action addressed to a
    // different surface targets a component that is not on this one, folded
    // into unknownComponent (the spike-5 fold; no dedicated reason).
    final boundSurface = surface.surfaceId;
    if (boundSurface != null && event.surfaceId != boundSurface) {
      return Rejected(
        kind: RejectionKind.unknownComponent,
        action: event.name,
        componentId: event.sourceComponentId,
      );
    }

    // Gate 1b — exists/mounted. Walk the live tree FRESH (no cached refs, A8),
    // collecting EVERY mounted branch under this id.
    final matches = _mountedMatches(root, event.sourceComponentId);
    if (matches.isEmpty) {
      return Rejected(
        kind: _everSeenIds.contains(event.sourceComponentId)
            ? RejectionKind.staleUnmounted
            : RejectionKind.unknownComponent,
        action: event.name,
        componentId: event.sourceComponentId,
      );
    }
    if (matches.length > 1) {
      // A component id reachable from two parents is built once per reference
      // (buildSeedTree's DAG-share semantics, A19), so the live tree holds
      // multiple distinct branches under one id, each with its own state. The
      // hit-test target is then ambiguous and enforcement would silently
      // mutate an arbitrary copy — a developer/authoring error (a surface must
      // address each component by a unique id), never actor feedback.
      throw StateError(
        'component "${event.sourceComponentId}" resolves to '
        '${matches.length} mounted branches — the emission shares this id '
        'across parents (a DAG share; buildSeedTree builds it once per '
        'reference). consent cannot unambiguously enforce an action against a '
        'duplicated id; a surface must address each component by a unique id.',
      );
    }
    final target = matches.single;

    // Gate 2 — catalog-declared. The live component's wire type must declare
    // the action; this is the same `actions` data the LLM saw as `x-actions`.
    final wireType = _typeById[event.sourceComponentId];
    final declared = wireType == null
        ? const <String, ActionDeclaration>{}
        : (catalog.typeNamed(wireType)?.actions ??
              const <String, ActionDeclaration>{});
    if (!declared.containsKey(event.name)) {
      return Rejected(
        kind: RejectionKind.undeclaredAction,
        action: event.name,
        componentId: event.sourceComponentId,
        availableActions: declared.keys.toList()..sort(),
      );
    }

    final handler = _actionableOf(target);

    // Gate 3 — payload. Pure validation, delegated to the target state; a
    // throw leaves the tree untouched (no mutation has happened yet).
    try {
      handler.validateAction(event.name, event.payload);
    } on ActionPayloadException catch (e) {
      return Rejected(
        kind: RejectionKind.badPayload,
        action: event.name,
        componentId: event.sourceComponentId,
        payloadError: e.message,
      );
    }

    // Enforce — apply through the target state (Decision 4); the rebuild flows
    // through the standard dirty/flush pipeline when the owner next flushes.
    final change = handler.applyAction(event.name, event.payload);
    return Applied(
      action: event.name,
      componentId: event.sourceComponentId,
      change: change,
    );
  }

  /// Returns every mounted branch whose key equals [id], walking the live tree
  /// fresh from [root] in tree order. Normally a singleton; more than one means
  /// the emission shared this id across parents (a DAG share — built once per
  /// reference by buildSeedTree, A19), which [route] rejects as ambiguous. The
  /// walk descends transparently through component branches (`visitChildren`
  /// composes), so a target nested under `Watch`/stateless wrappers is still
  /// found. No branch refs are cached between calls — staleness is detected by
  /// re-walking (A8).
  List<Branch> _mountedMatches(Branch root, String id) {
    final matches = <Branch>[];
    void walk(Branch branch) {
      if (branch.mounted && branch.key == id) matches.add(branch);
      branch.visitChildren(walk);
    }

    walk(root);
    return matches;
  }

  /// Resolves the [Actionable] dispatch seam for a resolved target branch
  /// (ADR-0005 Decision 4 — "applied via the target state").
  ///
  /// The target must be a [StatefulBranch] whose state implements [Actionable].
  /// This is the one place consent reaches a live `State`; it does so through
  /// `StatefulBranch.state` — the action-dispatch seam spike 5 flagged as a
  /// production need (register pending). Reaching the target state is exactly
  /// what Decision 4 mandates, so this use is the ADR-sanctioned exception to
  /// the getter's general "test-only" guidance.
  ///
  /// Throws [StateError] when a component whose catalog type declares the
  /// action cannot honor it — the catalog and the component disagree, a
  /// developer wiring error rather than actor feedback.
  Actionable _actionableOf(Branch target) {
    if (target is StatefulBranch) {
      final state = target.state;
      if (state is Actionable) return state as Actionable;
    }
    throw StateError(
      'component "${target.key}" (${target.seed.runtimeType}) has a '
      'catalog-declared action but its live branch/state does not implement '
      'Actionable: the catalog affords an action the component cannot honor. '
      'Implement Actionable on the component\'s State (ADR-0005 Decision 4).',
    );
  }
}
