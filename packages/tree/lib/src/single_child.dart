/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
///
/// The single-child *link* vocabulary: a declarative way to stack a list of
/// wrapping seeds into a vertical spine — the `Nested`/`MultiProvider` shape,
/// generic (no inherited-value semantics baked in). `MultiChildSeed` composes N
/// children side-by-side; `Nest` composes N seeds top-to-bottom, each wrapping
/// the next down to a single leaf [Nest.child].
///
/// The layering mirrors `package:nested`. [SingleChildSeed] is a *marker
/// interface* — "I can be a link in a [Nest]". The single-child stateless and
/// stateful seeds are built directly on the [StatelessSeed]/[StatefulSeed]
/// primitives (adding only [SingleChildStatelessSeed.buildWithChild] /
/// [SingleChildState.buildWithChild]); their branches pick up
/// [SingleChildBranchMixin], which injects the enclosing chain's downstream at
/// build. Because a [SingleChildState] *extends* [State] (rather than being a
/// `mixin on State`), a `mixin FooBehavior on State` composes onto both a plain
/// state and a single-child one.
///
/// `Nest` is itself a [SingleChildSeed], so a `Nest` can be a link inside
/// another `Nest`: its own leaf may then be null and the enclosing chain
/// supplies it.
library;

import 'package:meta/meta.dart';

import 'branch.dart';
import 'key.dart';
import 'seed.dart';
import 'stateful.dart';
import 'stateless.dart';
import 'tree_context.dart';

// Shared message for a single-child seed asked to build with no child from
// either source (standalone with `child: null`, or somehow outside a Nest).
String _noChildMessage(Object runtimeType) =>
    '$runtimeType has no child to wrap: set `child:` for standalone use, or '
    'place it in a `Nest` (which supplies each link its downstream).';

/// Marker interface for a [Seed] that can slot into a [Nest] as a link — the
/// single-child analogue of `package:nested`'s `SingleChildWidget`.
///
/// A `SingleChildSeed` wraps a single downstream [child]. Used standalone it
/// wraps its own [child]; placed in a [Nest] the enclosing chain supplies the
/// downstream (the next link, or the leaf for the last) and the seed's own
/// [child] may be null.
///
/// Its branch is required to carry [SingleChildBranchMixin] — that is how the
/// injected downstream reaches the build. Implement by subclassing
/// [SingleChildStatelessSeed] / [SingleChildStatefulSeed], or as `Nest` does.
abstract interface class SingleChildSeed implements Seed {
  /// The downstream subtree this seed wraps when used standalone. Null means
  /// "supplied by an enclosing [Nest]".
  Seed? get child;

  /// A single-child seed's branch must mix in [SingleChildBranchMixin] so an
  /// enclosing [Nest] can inject its downstream.
  @override
  SingleChildBranchMixin createBranch();
}

/// The branch-side capability that lets a [SingleChildSeed]'s branch receive a
/// downstream injected by an enclosing [Nest] — the analogue of `nested`'s
/// `SingleChildWidgetElementMixin`.
///
/// At mount it captures the enclosing chain link (if any); [injectedChild] is
/// the downstream that link supplies, or null when the branch is standalone.
mixin SingleChildBranchMixin on Branch {
  _NestHookBranch? _hook;

  /// The downstream supplied by the enclosing [Nest] link, or null when this
  /// branch is used standalone (outside a chain).
  @protected
  Seed? get injectedChild => _hook?.injected;

  @override
  void mount(Branch? parent, Object? slot) {
    if (parent is _NestHookBranch) _hook = parent;
    super.mount(parent, slot);
  }
}

/// A [SingleChildSeed] that composes purely from its own configuration — the
/// single-child `StatelessSeed`, built directly on [StatelessSeed].
///
/// Override [buildWithChild] to describe the subtree, embedding the supplied
/// downstream `child` wherever it belongs (e.g. `Frame(child: child)`).
abstract class SingleChildStatelessSeed extends StatelessSeed
    implements SingleChildSeed {
  /// Creates a stateless single-child seed wrapping [child] (null when placed
  /// in a [Nest]), optionally [key]ed.
  const SingleChildStatelessSeed({this.child, super.key});

  @override
  final Seed? child;

  /// Describes the subtree for this configuration, embedding [child] (the
  /// downstream link or leaf). [context] is the branch's capability handle,
  /// never the branch itself.
  @protected
  Seed buildWithChild(TreeContext context, Seed child);

  /// Standalone build: wraps this seed's own [child]. Inside a [Nest] the
  /// branch injects the chain's downstream instead (see
  /// [SingleChildStatelessBranch]).
  @override
  Seed build(TreeContext context) {
    final c = child;
    if (c == null) throw StateError(_noChildMessage(runtimeType));
    return buildWithChild(context, c);
  }

  @override
  SingleChildStatelessBranch createBranch() => SingleChildStatelessBranch(this);
}

/// Mounted branch for a [SingleChildStatelessSeed]: a [StatelessBranch] that,
/// inside a [Nest], builds with the injected downstream instead of the seed's
/// own child.
class SingleChildStatelessBranch extends StatelessBranch
    with SingleChildBranchMixin {
  /// Creates the branch for [seed].
  SingleChildStatelessBranch(SingleChildStatelessSeed super.seed);

  @override
  Seed build(TreeContext context) {
    final injected = injectedChild;
    if (injected != null) {
      return (seed as SingleChildStatelessSeed).buildWithChild(
        context,
        injected,
      );
    }
    return super.build(context);
  }
}

/// A [SingleChildSeed] whose branch owns mutable [SingleChildState] — the
/// single-child `StatefulSeed`, built directly on [StatefulSeed].
abstract class SingleChildStatefulSeed extends StatefulSeed
    implements SingleChildSeed {
  /// Creates a stateful single-child seed wrapping [child] (null when placed in
  /// a [Nest]), optionally [key]ed.
  const SingleChildStatefulSeed({this.child, super.key});

  @override
  final Seed? child;

  /// Creates the mutable state for a branch of this seed.
  @override
  @factory
  SingleChildState<SingleChildStatefulSeed> createState();

  @override
  SingleChildStatefulBranch createBranch() => SingleChildStatefulBranch(this);
}

/// Mutable state for a [SingleChildStatefulSeed] — a [State] that describes its
/// subtree through [buildWithChild], with the full
/// initState/didChangeDependencies/setState/dispose lifecycle inherited.
///
/// It *extends* [State] (not `mixin on State`), so a shared
/// `mixin FooBehavior on State` composes onto both a plain [State] and a
/// single-child one.
abstract class SingleChildState<T extends SingleChildStatefulSeed>
    extends State<T> {
  /// Describes the subtree for the current configuration and state, embedding
  /// [child] (the downstream link or leaf).
  @protected
  Seed buildWithChild(TreeContext context, Seed child);

  /// Standalone build: wraps the seed's own [SingleChildSeed.child]. Inside a
  /// [Nest] the branch injects the chain's downstream instead.
  @override
  Seed build(TreeContext context) {
    final c = seed.child;
    if (c == null) throw StateError(_noChildMessage(seed.runtimeType));
    return buildWithChild(context, c);
  }
}

/// Mounted branch for a [SingleChildStatefulSeed]: a [StatefulBranch] — full
/// [State] lifecycle inherited — that, inside a [Nest], builds with the
/// injected downstream instead of the seed's own child.
class SingleChildStatefulBranch extends StatefulBranch
    with SingleChildBranchMixin {
  /// Creates the branch and its [SingleChildState] for [seed].
  SingleChildStatefulBranch(SingleChildStatefulSeed super.seed);

  @override
  Seed build(TreeContext context) {
    final injected = injectedChild;
    if (injected != null) {
      return (state as SingleChildState).buildWithChild(context, injected);
    }
    return super.build(context);
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
/// `Nest` is itself a [SingleChildSeed], so a `Nest` can be a link inside
/// another `Nest`; when it is, its [child] may be null and the enclosing chain
/// supplies the leaf (the nested chain flattens into the outer one).
///
/// Fully `const`-constructible: the [children] are referenced as authored and
/// never reconstructed — each link's downstream is supplied at the branch
/// layer, not by copying seeds. An empty [children] mounts the leaf directly.
class Nest extends Seed implements SingleChildSeed {
  /// Creates a chain that wraps [child] with each of [children] in order (the
  /// first is outermost), optionally [key]ed. [child] is the leaf; leave it
  /// null only when placing this `Nest` inside another `Nest`, which then
  /// supplies the leaf.
  const Nest({required this.children, this.child, super.key});

  /// The wrapping seeds, outermost first. Each is placed as the parent of the
  /// next; the last wraps the leaf.
  final List<SingleChildSeed> children;

  /// The leaf subtree at the bottom of the chain. Null means "supplied by an
  /// enclosing [Nest]".
  @override
  final Seed? child;

  @override
  NestBranch createBranch() => NestBranch(this);
}

/// Mounted branch for a [Nest]: folds the declared chain into a spine of hook
/// branches and keeps it reconciled.
///
/// Each rebuild refolds [Nest.children] into fresh internal [_NestHook]
/// carriers (innermost-out), so a change to a downstream link or the leaf
/// propagates through otherwise-identical intermediate links — the Flutter
/// `nested` behaviour, where rebuilding the chain rebuilds all of it. When the
/// `Nest` itself is reused unchanged, the parent's identical-config fast path
/// prunes the whole chain before this hook runs.
///
/// `NestBranch` carries [SingleChildBranchMixin] so a `Nest` used as a link in
/// an enclosing `Nest` takes its leaf from the injected downstream.
class NestBranch extends Branch with SingleChildBranchMixin {
  /// Creates the branch for [seed].
  NestBranch(Nest super.seed);

  Branch? _head;

  /// The head of the mounted chain (the outermost link's hook branch, or the
  /// leaf's branch when [Nest.children] is empty). Exposed for testing.
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
    // children.first ends up outermost. The hooks are fresh every build (the
    // downstream-change propagation guarantee) and reference the user seeds
    // as-is (no reconstruction — Nest stays const-constructible).
    final children = _nest.children;
    Seed acc = _leaf();
    for (var i = children.length - 1; i >= 0; i--) {
      acc = _NestHook(children[i], acc);
    }
    _head = updateChild(_head, acc, 0);
  }

  // The leaf at the bottom of this chain: the injected downstream when this
  // `Nest` is a link in an enclosing `Nest`, else the seed's own child.
  Seed _leaf() {
    final injected = injectedChild;
    if (injected != null) return injected;
    final own = _nest.child;
    if (own == null) {
      throw StateError(
        'Nest has no leaf to wrap: set `child:` for standalone use, or place '
        'it in an enclosing `Nest` (which supplies the leaf).',
      );
    }
    return own;
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

// --- internal chain hook ---------------------------------------------------

/// Internal chain link pairing a user [node] with its resolved downstream
/// [injected]. Mirrors `nested`'s `_NestedHook`: it is the parent of the node's
/// own branch, and the source that branch reads its injected downstream from
/// (via [SingleChildBranchMixin]). This lets `Nest` supply a downstream without
/// reconstructing the user's (const) seeds.
///
/// Its key encodes the node's identity — the user key if any, else the node's
/// runtimeType — so that at a fixed chain position a same-type node reconciles
/// in place (preserving stateful state) while a type change remounts (fresh
/// state), even though every hook shares runtimeType `_NestHook`.
class _NestHook extends Seed {
  _NestHook(this.node, this.injected)
    : super(key: node.key ?? ValueKey<Type>(node.runtimeType));

  final SingleChildSeed node;
  final Seed injected;

  @override
  _NestHookBranch createBranch() => _NestHookBranch(this);
}

/// Branch for a [_NestHook]: mounts the node's own branch as its child and
/// exposes the [injected] downstream to it. Mirroring `nested`'s injectedChild
/// setter, it forces that child to rebuild when only the downstream changed —
/// the node instance is reused across a chain rebuild, so reconciliation would
/// otherwise skip it and the new downstream would never reach the leaf.
class _NestHookBranch extends Branch {
  _NestHookBranch(_NestHook super.seed);

  Branch? _child;

  _NestHook get _hookSeed => seed as _NestHook;

  /// The downstream this link supplies to its wrapped node.
  Seed get injected => _hookSeed.injected;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _child = updateChild(_child, _hookSeed.node, 0);
  }

  @override
  void update(Seed newSeed) {
    final old = _hookSeed;
    super.update(newSeed);
    final now = _hookSeed;
    // performRebuild (run by super.update) reconciles the wrapped node. The
    // node instance is reused across a chain rebuild, so its updateChild takes
    // the identical-config fast path and does not rebuild it. When only the
    // injected downstream changed, force the wrapped node to rebuild so it
    // re-reads the new downstream — nested's `visitChildren(markNeedsBuild)`,
    // done synchronously to match the update cascade. A node that itself
    // changed was already rebuilt by performRebuild, so skip the force.
    if (identical(old.node, now.node) &&
        !identical(old.injected, now.injected)) {
      _child?.rebuild(force: true);
    }
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}
