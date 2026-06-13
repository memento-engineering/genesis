/// The receive side of the dialogue: a live surface that mounts an
/// `updateComponents` message onto a `genesis_tree` and reconciles
/// re-emissions by key (ADR-0003 Decisions 2 and 3).
///
/// Component ids become `Seed` keys (tree keys == A2UI component ids), which
/// is what turns whole-tree re-emission into an identity-preserving patch:
/// the root survives because `id == "root"` is a stable key and `canUpdate`
/// holds; kept children are reconciled in place at their new index; removed
/// ids are unmounted; new ids are mounted fresh.
library;

import 'package:genesis_taxonomy/genesis_taxonomy.dart'
    show ComponentRegistry, buildSeedTree;
import 'package:genesis_tree/genesis_tree.dart';

import 'envelope.dart';

/// The id of the root component, by A2UI v0.9 convention (no `rootId` field).
const String rootComponentId = 'root';

/// A live, mountable surface driven by A2UI v0.9 `updateComponents` messages.
///
/// dialogue is registry-agnostic: the [ComponentRegistry] is injected via the
/// constructor, so the surface deserializes against whatever catalog the
/// consumer generated (the wire type names map to the consumer's `Seed`
/// species). The surface owns a [TreeOwner]; a renderer (e.g.
/// genesis_typesetting) would mount the *same* owner to draw the tree.
///
/// Lifecycle:
///
/// - [mount] builds the first tree from a message and roots it on the owner;
/// - [apply] reconciles a subsequent message against the mounted tree by key,
///   preserving identity (ADR-0003 Decision 3).
final class DialogueSurface {
  /// Creates a surface that deserializes through [registry] onto [owner].
  ///
  /// [owner] defaults to a fresh [TreeOwner]; inject one to share a single
  /// owner with a renderer.
  DialogueSurface({required this.registry, TreeOwner? owner})
    : owner = owner ?? TreeOwner();

  /// The catalog-bound registry deserialization goes through (injected;
  /// dialogue hardcodes no component type names).
  final ComponentRegistry registry;

  /// The tree owner this surface roots its tree on. Exposed so a renderer can
  /// mount the same owner and observe flushes.
  final TreeOwner owner;

  Branch? _rootBranch;

  /// The mounted root branch, or null before [mount]. Exposed for inspection
  /// and rendering.
  Branch? get rootBranch => _rootBranch;

  /// The surface id of the last mounted/applied message, or null before
  /// [mount].
  String? get surfaceId => _surfaceId;
  String? _surfaceId;

  /// Mounts [message] as the initial tree: deserializes the flat components
  /// into a keyed `Seed` tree (root by `id == "root"`) through the registry,
  /// roots it on the owner, and returns the mounted root [Branch].
  ///
  /// Throws if already mounted (call [apply] for subsequent messages).
  /// Deserialization faults (dangling child id, duplicate id, cycle, unknown
  /// type, bad props) surface as `genesis_taxonomy` `TaxonomyException`s.
  Branch mount(UpdateComponents message) {
    if (_rootBranch != null) {
      throw StateError(
        'DialogueSurface already mounted; use apply() to reconcile a '
        'subsequent updateComponents message',
      );
    }
    final rootSeed = buildSeedTree(
      registry,
      message.components,
      rootId: rootComponentId,
    );
    _surfaceId = message.surfaceId;
    return _rootBranch = owner.mountRoot(rootSeed);
  }

  /// Reconciles [message] against the mounted tree **by key**, preserving
  /// element identity (ADR-0003 Decision 3).
  ///
  /// Builds the new keyed `Seed` tree from the message and calls
  /// `rootBranch.update(newRootSeed)`: the root id is `"root"` (a stable key)
  /// and the root type is unchanged, so `canUpdate` holds and the root
  /// branch updates in place, reconciling its children by key. Kept ids keep
  /// their `Branch` instances (reordered at their new index, deep into moved
  /// subtrees); a prop-changed id keeps its instance with the new seed;
  /// removed ids are unmounted (`.mounted == false`); inserted ids are
  /// mounted fresh.
  ///
  /// Honest limit (ADR-0001's A18 fast path): the fast path skips only on
  /// `identical()` seeds, and freshly *deserialized* seeds are never
  /// identical — so re-applying a byte-identical message does not short-circuit
  /// the reconcile. Keyed identity preservation still holds; only the skip
  /// optimization does not fire on the wire path.
  ///
  /// Throws [StateError] if called before [mount].
  void apply(UpdateComponents message) {
    final root = _rootBranch;
    if (root == null) {
      throw StateError('DialogueSurface not mounted; call mount() first');
    }
    final newRootSeed = buildSeedTree(
      registry,
      message.components,
      rootId: rootComponentId,
    );
    _surfaceId = message.surfaceId;
    root.update(newRootSeed);
  }
}
