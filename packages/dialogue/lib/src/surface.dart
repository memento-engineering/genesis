/// The receive side of the dialogue: a live surface that mounts an
/// `updateComponents` message onto a `genesis_tree` and reconciles
/// re-emissions by key.
///
/// Component ids become `Component` keys (tree keys == A2UI component ids), which
/// is what turns whole-tree re-emission into an identity-preserving patch:
/// the root survives because `id == "root"` is a stable key and `canUpdate`
/// holds; kept children are reconciled in place at their new index; removed
/// ids are unmounted; new ids are mounted fresh.
library;

import 'package:genesis_taxonomy/genesis_taxonomy.dart'
    show ComponentRegistry, buildComponentTree;
import 'package:genesis_tree/genesis_tree.dart';

import 'envelope.dart';

/// The id of the root component, by A2UI v0.9 convention (no `rootId` field).
const String rootComponentId = 'root';

/// A live, mountable surface driven by A2UI v0.9 `updateComponents` messages.
///
/// dialogue is registry-agnostic: the [ComponentRegistry] is injected via the
/// constructor, so the surface deserializes against whatever catalog the
/// consumer generated (the wire type names map to the consumer's `Component`
/// species). The surface owns a [BuildOwner]; a renderer (e.g.
/// genesis_typesetting) would mount the *same* owner to draw the tree.
///
/// Lifecycle:
///
/// - [mount] builds the first tree from a message and roots it on the owner;
/// - [apply] reconciles a subsequent message against the mounted tree by key,
///   preserving identity.
final class DialogueSurface {
  /// Creates a surface that deserializes through [registry] onto [owner].
  ///
  /// [owner] defaults to a fresh [BuildOwner]; inject one to share a single
  /// owner with a renderer.
  DialogueSurface({required this.registry, BuildOwner? owner})
    : owner = owner ?? BuildOwner();

  /// The catalog-bound registry deserialization goes through (injected;
  /// dialogue hardcodes no component type names).
  final ComponentRegistry registry;

  /// The tree owner this surface roots its tree on. Exposed so a renderer can
  /// mount the same owner and observe flushes.
  final BuildOwner owner;

  Element? _rootElement;

  /// The mounted root element, or null before [mount]. Exposed for inspection
  /// and rendering.
  Element? get rootElement => _rootElement;

  /// Legacy spelling for [rootElement].
  @Deprecated('Use rootElement instead.')
  Element? get rootBranch => rootElement;

  /// The surface id of the last mounted/applied message, or null before
  /// [mount].
  String? get surfaceId => _surfaceId;
  String? _surfaceId;

  /// Mounts [message] as the initial tree: deserializes the flat components
  /// into a keyed `Component` tree (root by `id == "root"`) through the registry,
  /// roots it on the owner, and returns the mounted root [Element].
  ///
  /// Throws if already mounted (call [apply] for subsequent messages).
  /// Deserialization faults (dangling child id, duplicate id, cycle, unknown
  /// type, bad props) surface as `genesis_taxonomy` `TaxonomyException`s.
  Element mount(UpdateComponents message) {
    if (_rootElement != null) {
      throw StateError(
        'DialogueSurface already mounted; use apply() to reconcile a '
        'subsequent updateComponents message',
      );
    }
    final rootComponent = buildComponentTree(
      registry,
      message.components,
      rootId: rootComponentId,
    );
    final element = owner.mountRoot(rootComponent);
    _surfaceId = message.surfaceId;
    return _rootElement = element;
  }

  /// Reconciles [message] against the mounted tree **by key**, preserving
  /// element identity.
  ///
  /// Builds the new keyed `Component` tree from the message and calls
  /// `rootElement.update(newRootComponent)`: the root id is `"root"` (a stable key)
  /// and its component type is immutable across re-emissions, so the root
  /// element updates in place, reconciling its children by key. Kept ids keep
  /// their `Element` instances (reordered at their new index, deep into moved
  /// subtrees); a prop-changed id keeps its instance with the new component;
  /// removed ids are unmounted (`.mounted == false`); inserted ids are
  /// mounted fresh.
  ///
  /// Honest limit (the reconcile fast path): the fast path skips only on
  /// `identical()` seeds, and freshly *deserialized* seeds are never
  /// identical — so re-applying a byte-identical message does not short-circuit
  /// the reconcile. Keyed identity preservation still holds; only the skip
  /// optimization does not fire on the wire path.
  ///
  /// Throws [StateError] if called before [mount], or if the message changes
  /// the root component type. The surface performs this compatibility check
  /// in release mode before it touches the mounted tree.
  void apply(UpdateComponents message) {
    final root = _rootElement;
    if (root == null) {
      throw StateError('DialogueSurface not mounted; call mount() first');
    }
    final newRootComponent = buildComponentTree(
      registry,
      message.components,
      rootId: rootComponentId,
    );
    if (!Component.canUpdate(root.component, newRootComponent)) {
      throw StateError(
        'DialogueSurface.apply: incompatible root component for component id '
        '"$rootComponentId" — the mounted root is ${root.component.runtimeType} '
        'and this message builds a ${newRootComponent.runtimeType}. The root '
        'component type is immutable across re-emissions: the surface has no '
        'teardown/remount path, so a root-type change is rejected here rather '
        'than corrupting the mounted tree. Re-emit the same root component '
        'type, or build a new surface.',
      );
    }
    root.update(newRootComponent);
    // Committed only after a successful update: a throwing update must not
    // leave the surface metadata describing a message the tree never took.
    _surfaceId = message.surfaceId;
  }
}
