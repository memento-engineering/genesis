/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
///
/// The single-child *chain* vocabulary: a declarative way to stack a list of
/// wrapping seeds into a vertical spine — the `Nested`/`MultiProvider` shape,
/// generic (no inherited-value semantics baked in). `MultiChildSeed` composes N
/// children side-by-side; `Nest` composes N seeds top-to-bottom, each wrapping
/// the next down to a single leaf [child].
///
/// A `SingleChildSeed` is the `StatelessSeed`/`StatefulSeed` analogue with one
/// difference: its build receives the downstream [child] to embed
/// ([SingleChildStatelessSeed.buildWithChild] /
/// [SingleChildState.buildWithChild]). Used standalone it embeds its own
/// [SingleChildSeed.child]; placed in a [Nest] it embeds the next link.
library;

import 'package:meta/meta.dart';

import 'branch.dart';
import 'component_branch.dart';
import 'key.dart';
import 'seed.dart';
import 'tree_context.dart';
import 'tree_owner.dart';

/// A [Seed] that wraps a single downstream [child] — the base of the vertical
/// [Nest] chain vocabulary and the single-child analogue of `StatelessSeed` /
/// `StatefulSeed`.
///
/// Subclass [SingleChildStatelessSeed] or [SingleChildStatefulSeed], not this
/// directly. [child] is the downstream subtree: set it for standalone use, or
/// leave it null and place the seed in a [Nest], which supplies each link's
/// downstream (the next link, or the leaf for the last).
abstract class SingleChildSeed extends Seed {
  /// Creates a single-child seed wrapping [child] (null when placed in a
  /// [Nest]), optionally [key]ed.
  const SingleChildSeed({this.child, super.key});

  /// The downstream subtree this seed wraps. Null means "supplied by an
  /// enclosing [Nest]"; a standalone seed must set it.
  final Seed? child;
}

// Shared message for a single-child seed asked to build with no child from
// either source (standalone with `child: null`, or somehow outside a Nest).
String _noChildMessage(Object runtimeType) =>
    '$runtimeType has no child to wrap: set `child:` for standalone use, or '
    'place it in a `Nest` (which supplies each link its downstream).';

/// A [SingleChildSeed] that composes purely from its own configuration — the
/// single-child `StatelessSeed`.
///
/// Override [buildWithChild] to describe the subtree, embedding the supplied
/// downstream `child` wherever it belongs (e.g. `Frame(child: child)`).
abstract class SingleChildStatelessSeed extends SingleChildSeed {
  /// Creates a stateless single-child seed wrapping [child], optionally [key]ed.
  const SingleChildStatelessSeed({super.child, super.key});

  /// Describes the subtree for this configuration, embedding [child] (the
  /// downstream link or leaf). [context] is the branch's capability handle,
  /// never the branch itself.
  @protected
  Seed buildWithChild(TreeContext context, Seed child);

  @override
  SingleChildStatelessBranch createBranch() => SingleChildStatelessBranch(this);
}

/// Mounted branch for a standalone [SingleChildStatelessSeed]: delegates
/// [build] to the seed with the seed's own [SingleChildSeed.child].
class SingleChildStatelessBranch extends ComponentBranch {
  /// Creates the branch for [seed].
  SingleChildStatelessBranch(SingleChildStatelessSeed super.seed);

  @override
  Seed build(TreeContext context) {
    final s = seed as SingleChildStatelessSeed;
    final child = s.child;
    if (child == null) throw StateError(_noChildMessage(s.runtimeType));
    return s.buildWithChild(context, child);
  }
}

/// A [SingleChildSeed] whose branch owns mutable [SingleChildState] — the
/// single-child `StatefulSeed`.
abstract class SingleChildStatefulSeed extends SingleChildSeed {
  /// Creates a stateful single-child seed wrapping [child], optionally [key]ed.
  const SingleChildStatefulSeed({super.child, super.key});

  /// Creates the mutable state for a branch of this seed.
  @factory
  SingleChildState<SingleChildStatefulSeed> createState();

  @override
  SingleChildStatefulBranch createBranch() => SingleChildStatefulBranch(this);
}

/// Mutable state owned by a stateful single-child branch, with the
/// initState/didChangeDependencies/buildWithChild/dispose lifecycle — the
/// single-child `State`.
abstract class SingleChildState<T extends SingleChildStatefulSeed> {
  /// The current [SingleChildStatefulSeed] configuration of the owning branch.
  T get seed => _branch!.nodeSeed as T;

  /// The owning branch's capability handle: a separate object, never the
  /// branch itself; throws [StateError] when used after unmount.
  TreeContext get context {
    assert(_branch != null, 'context accessed outside branch lifecycle');
    return _branch!.context;
  }

  _StatefulSingleChildBranch? _branch;

  /// Called exactly once, before the first build.
  @protected
  void initState() {}

  /// Called after [initState] and whenever a depended-on inherited value
  /// changes, before the next build.
  @protected
  void didChangeDependencies() {}

  /// Describes the subtree for the current configuration and state, embedding
  /// [child] (the downstream link or leaf).
  Seed buildWithChild(TreeContext context, Seed child);

  /// Called when the owning branch unmounts, before the subtree is released.
  @protected
  void dispose() {}

  /// The setState analogue: applies [fn], then marks the owning branch as
  /// needing rebuild.
  void setState(VoidCallback fn) {
    fn();
    _branch!.markNeedsRebuild();
  }
}

// Shared lifecycle for stateful single-child branches (standalone and in-Nest);
// the concrete subclasses only supply where the node seed and downstream child
// come from. Mirrors StatefulBranch's initState/didChangeDependencies flow.
abstract class _StatefulSingleChildBranch extends ComponentBranch {
  _StatefulSingleChildBranch(super.seed) {
    _state = nodeSeed.createState();
    _state._branch = this;
  }

  late final SingleChildState<SingleChildStatefulSeed> _state;
  bool _firstBuild = true;
  bool _needsDidChangeDependencies = false;

  /// The user's stateful node seed (the seed itself when standalone; the
  /// wrapped node when in a [Nest]). Read by [SingleChildState.seed].
  SingleChildStatefulSeed get nodeSeed;

  /// The downstream subtree to embed (the seed's own child when standalone; the
  /// next link/leaf when in a [Nest]).
  Seed get effectiveChild;

  @override
  Seed build(TreeContext context) =>
      _state.buildWithChild(context, effectiveChild);

  @override
  void dependencyChanged() {
    _needsDidChangeDependencies = true;
    markNeedsRebuild();
  }

  @override
  void performRebuild() {
    if (_firstBuild) {
      _firstBuild = false;
      _state.initState();
      _needsDidChangeDependencies = true;
    }
    if (_needsDidChangeDependencies) {
      _needsDidChangeDependencies = false;
      _state.didChangeDependencies();
    }
    super.performRebuild();
  }

  @override
  void unmount() {
    _state.dispose();
    super.unmount();
  }
}

/// Mounted branch for a standalone [SingleChildStatefulSeed]: reads its node
/// and downstream child from the seed's own configuration.
class SingleChildStatefulBranch extends _StatefulSingleChildBranch {
  /// Creates the branch and its [SingleChildState] for [seed].
  SingleChildStatefulBranch(SingleChildStatefulSeed super.seed);

  @override
  SingleChildStatefulSeed get nodeSeed => seed as SingleChildStatefulSeed;

  @override
  Seed get effectiveChild {
    final child = nodeSeed.child;
    if (child == null) throw StateError(_noChildMessage(nodeSeed.runtimeType));
    return child;
  }
}

/// A [Seed] that stacks a list of [SingleChildSeed]s into a vertical chain,
/// each wrapping the next down to a single leaf [child] — the generic
/// `Nested`/`MultiProvider` shape, and the vertical sibling of
/// `MultiChildSeed`'s horizontal fan-out.
///
/// ```dart
/// Nest(
///   children: [Frame(...), Padding(...), Focus()],
///   child: Content(),
/// )
/// // ⇒ Frame(child: Padding(child: Focus(child: Content())))
/// ```
///
/// Fully `const`-constructible: the [children] are referenced as authored and
/// never reconstructed — each link's downstream is supplied at the branch
/// layer, not by copying seeds. An empty [children] mounts [child] directly.
class Nest extends Seed {
  /// Creates a chain that wraps [child] with each of [children] in order (the
  /// first is outermost), optionally [key]ed.
  const Nest({required this.children, required this.child, super.key});

  /// The wrapping seeds, outermost first. Each is placed as the parent of the
  /// next; the last wraps [child].
  final List<SingleChildSeed> children;

  /// The leaf subtree at the bottom of the chain.
  final Seed child;

  @override
  NestBranch createBranch() => NestBranch(this);
}

/// Mounted branch for a [Nest]: folds the declared chain into a spine of link
/// branches and keeps it reconciled.
///
/// Each rebuild refolds [Nest.children] into fresh internal carrier seeds
/// (innermost-out), so a change to a downstream link or the leaf propagates
/// through otherwise-identical intermediate links — the Flutter `nested`
/// behaviour, where rebuilding the chain rebuilds all of it. When the `Nest`
/// itself is reused unchanged, the parent's identical-config fast path prunes
/// the whole chain before this hook runs.
class NestBranch extends Branch {
  /// Creates the branch for [seed].
  NestBranch(Nest super.seed);

  Branch? _head;

  /// The head of the mounted chain (the outermost link's branch, or the leaf's
  /// branch when [Nest.children] is empty). Exposed for testing.
  /// Do not use in production code.
  Branch? get head => _head;

  Nest get _nest => seed as Nest;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    // Fold innermost-out: wrap the leaf, then each child from the last up, so
    // children.first ends up outermost. The carriers are fresh every build (the
    // downstream-change propagation guarantee) and reference the user seeds
    // as-is (no reconstruction — Nest stays const-constructible).
    final children = _nest.children;
    Seed acc = _nest.child;
    for (var i = children.length - 1; i >= 0; i--) {
      acc = _Link(children[i], acc);
    }
    _head = updateChild(_head, acc, 0);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    final head = _head;
    if (head != null) visitor(head);
  }

  @override
  void unmount() {
    _head = updateChild(_head, null, 0);
    super.unmount();
  }
}

// --- internal chain carrier ------------------------------------------------

/// Internal carrier pairing a user [node] with its resolved [next] downstream.
/// This is the seed that flows as each link's child, letting `Nest` supply a
/// downstream without reconstructing the user's (const) seeds.
///
/// Its key encodes the node's identity — the user key if any, else the node's
/// runtimeType — so that at a fixed chain position a same-type node reconciles
/// in place (preserving stateful state) while a type change at that position
/// remounts (fresh state), even though every carrier shares runtimeType `_Link`.
class _Link extends Seed {
  _Link(this.node, this.next)
    : super(key: node.key ?? ValueKey<Type>(node.runtimeType));

  final SingleChildSeed node;
  final Seed next;

  @override
  Branch createBranch() => node is SingleChildStatefulSeed
      ? _StatefulLinkBranch(this)
      : _StatelessLinkBranch(this);
}

/// Link branch for a stateless node inside a [Nest]: builds the node with the
/// carrier's [_Link.next] as its downstream.
class _StatelessLinkBranch extends ComponentBranch {
  _StatelessLinkBranch(_Link super.seed);

  @override
  Seed build(TreeContext context) {
    final link = seed as _Link;
    return (link.node as SingleChildStatelessSeed).buildWithChild(
      context,
      link.next,
    );
  }
}

/// Link branch for a stateful node inside a [Nest]: same lifecycle as the
/// standalone branch, sourcing node and downstream from the carrier.
class _StatefulLinkBranch extends _StatefulSingleChildBranch {
  _StatefulLinkBranch(_Link super.seed);

  @override
  SingleChildStatefulSeed get nodeSeed =>
      (seed as _Link).node as SingleChildStatefulSeed;

  @override
  Seed get effectiveChild => (seed as _Link).next;
}
