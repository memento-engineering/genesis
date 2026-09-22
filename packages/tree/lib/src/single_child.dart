/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
///
/// The single-child *link* vocabulary: a declarative way to stack a list of
/// wrapping seeds into a vertical spine — the `Nested`/`MultiProvider` shape,
/// generic (no inherited-value semantics baked in). `MultiChildComponent` composes N
/// children side-by-side; `Nest` composes N seeds top-to-bottom, each wrapping
/// the next down to a single leaf [Nest.child].
///
/// The layering mirrors `package:nested`. [SingleChildComponent] is a *marker
/// interface* — "I can be a link in a [Nest]". The single-child stateless and
/// stateful seeds are built directly on the [StatelessComponent]/[StatefulComponent]
/// primitives (adding only [SingleChildStatelessComponent.buildWithChild] /
/// [SingleChildState.buildWithChild]); their elements pick up
/// [SingleChildElementMixin], which injects the enclosing chain's downstream at
/// build. Because a [SingleChildState] *extends* [State] (rather than being a
/// `mixin on State`), a `mixin FooBehavior on State` composes onto both a plain
/// state and a single-child one.
///
/// `Nest` is itself a [SingleChildComponent], so a `Nest` can be a link inside
/// another `Nest`: its own leaf may then be null and the enclosing chain
/// supplies it.
library;

import 'package:meta/meta.dart';

import 'element.dart';
import 'key.dart';
import 'component.dart';
import 'stateful.dart';
import 'stateless.dart';
import 'build_context.dart';

// Shared message for a single-child component asked to build with no child from
// either source (standalone with `child: null`, or somehow outside a Nest).
String _noChildMessage(Object runtimeType) =>
    '$runtimeType has no child to wrap: set `child:` for standalone use, or '
    'place it in a `Nest` (which supplies each link its downstream).';

/// Marker interface for a [Component] that can slot into a [Nest] as a link — the
/// single-child analogue of `package:nested`'s `SingleChildWidget`.
///
/// A `SingleChildComponent` wraps a single downstream [child]. Used standalone it
/// wraps its own [child]; placed in a [Nest] the enclosing chain supplies the
/// downstream (the next link, or the leaf for the last) and the component's own
/// [child] may be null.
///
/// Its element is required to carry [SingleChildElementMixin] — that is how the
/// injected downstream reaches the build. Implement by subclassing
/// [SingleChildStatelessComponent] / [SingleChildStatefulComponent], or as `Nest` does.
abstract interface class SingleChildComponent implements Component {
  /// The downstream subtree this component wraps when used standalone. Null means
  /// "supplied by an enclosing [Nest]".
  Component? get child;

  /// A single-child component's element must mix in [SingleChildElementMixin] so an
  /// enclosing [Nest] can inject its downstream.
  @override
  SingleChildElementMixin createElement();
}

/// The element-side capability that lets a [SingleChildComponent]'s element receive a
/// downstream injected by an enclosing [Nest] — the analogue of `nested`'s
/// `SingleChildWidgetElementMixin`.
///
/// At mount it captures the enclosing chain link (if any); [injectedChild] is
/// the downstream that link supplies, or null when the element is standalone.
mixin SingleChildElementMixin on Element {
  _NestHookElement? _hook;

  /// The downstream supplied by the enclosing [Nest] link, or null when this
  /// element is used standalone (outside a chain).
  @protected
  Component? get injectedChild => _hook?.injected;

  @override
  void mount(Element? parent, Object? slot) {
    if (parent is _NestHookElement) _hook = parent;
    super.mount(parent, slot);
  }
}

/// A [SingleChildComponent] that composes purely from its own configuration — the
/// single-child `StatelessComponent`, built directly on [StatelessComponent].
///
/// Override [buildWithChild] to describe the subtree, embedding the supplied
/// downstream `child` wherever it belongs (e.g. `Frame(child: child)`).
abstract class SingleChildStatelessComponent extends StatelessComponent
    implements SingleChildComponent {
  /// Creates a stateless single-child component wrapping [child] (null when placed
  /// in a [Nest]), optionally [key]ed.
  const SingleChildStatelessComponent({this.child, super.key});

  @override
  final Component? child;

  /// Describes the subtree for this configuration, embedding [child] (the
  /// downstream link or leaf). [context] is the element's capability handle,
  /// never the element itself.
  @protected
  Component buildWithChild(BuildContext context, Component child);

  /// Standalone build: wraps this component's own [child]. Inside a [Nest] the
  /// element injects the chain's downstream instead (see
  /// [SingleChildStatelessElement]).
  @override
  Component build(BuildContext context) {
    final c = child;
    if (c == null) throw StateError(_noChildMessage(runtimeType));
    return buildWithChild(context, c);
  }

  @override
  SingleChildStatelessElement createElement() =>
      SingleChildStatelessElement(this);

  @override
  @Deprecated('Use createElement instead.')
  SingleChildStatelessElement createBranch() => createElement();
}

/// Mounted element for a [SingleChildStatelessComponent]: a [StatelessElement] that,
/// inside a [Nest], builds with the injected downstream instead of the component's
/// own child.
class SingleChildStatelessElement extends StatelessElement
    with SingleChildElementMixin {
  /// Creates the element for [component].
  SingleChildStatelessElement(SingleChildStatelessComponent super.component);

  @override
  Component build(BuildContext context) {
    final injected = injectedChild;
    if (injected != null) {
      return (component as SingleChildStatelessComponent).buildWithChild(
        context,
        injected,
      );
    }
    return super.build(context);
  }
}

/// A [SingleChildComponent] whose element owns mutable [SingleChildState] — the
/// single-child `StatefulComponent`, built directly on [StatefulComponent].
abstract class SingleChildStatefulComponent extends StatefulComponent
    implements SingleChildComponent {
  /// Creates a stateful single-child component wrapping [child] (null when placed in
  /// a [Nest]), optionally [key]ed.
  const SingleChildStatefulComponent({this.child, super.key});

  @override
  final Component? child;

  /// Creates the mutable state for a element of this component.
  @override
  @factory
  SingleChildState<SingleChildStatefulComponent> createState();

  @override
  SingleChildStatefulElement createElement() =>
      SingleChildStatefulElement(this);

  @override
  @Deprecated('Use createElement instead.')
  SingleChildStatefulElement createBranch() => createElement();
}

/// Mutable state for a [SingleChildStatefulComponent] — a [State] that describes its
/// subtree through [buildWithChild], with the full
/// initState/didChangeDependencies/setState/dispose lifecycle inherited.
///
/// It *extends* [State] (not `mixin on State`), so a shared
/// `mixin FooBehavior on State` composes onto both a plain [State] and a
/// single-child one.
abstract class SingleChildState<T extends SingleChildStatefulComponent>
    extends State<T> {
  /// Describes the subtree for the current configuration and state, embedding
  /// [child] (the downstream link or leaf).
  @protected
  Component buildWithChild(BuildContext context, Component child);

  /// Standalone build: wraps the component's own [SingleChildComponent.child]. Inside a
  /// [Nest] the element injects the chain's downstream instead.
  @override
  Component build(BuildContext context) {
    final c = component.child;
    if (c == null) throw StateError(_noChildMessage(component.runtimeType));
    return buildWithChild(context, c);
  }
}

/// Mounted element for a [SingleChildStatefulComponent]: a [StatefulElement] — full
/// [State] lifecycle inherited — that, inside a [Nest], builds with the
/// injected downstream instead of the component's own child.
class SingleChildStatefulElement extends StatefulElement
    with SingleChildElementMixin {
  /// Creates the element and its [SingleChildState] for [component].
  SingleChildStatefulElement(SingleChildStatefulComponent super.component);

  @override
  Component build(BuildContext context) {
    final injected = injectedChild;
    if (injected != null) {
      return (state as SingleChildState).buildWithChild(context, injected);
    }
    return super.build(context);
  }
}

/// A [Component] that stacks a list of [SingleChildComponent]s into a vertical chain,
/// each wrapping the next down to a single leaf [child] — the generic
/// `Nested`/`MultiProvider` shape, and the vertical sibling of
/// `MultiChildComponent`'s horizontal fan-out.
///
/// ```dart
/// Nest(
///   children: [Frame(...), Padding(...), Focus()],
///   child: Content(),
/// )
/// // ⇒ Frame(child: Padding(child: Focus(child: Content())))
/// ```
///
/// `Nest` is itself a [SingleChildComponent], so a `Nest` can be a link inside
/// another `Nest`; when it is, its [child] may be null and the enclosing chain
/// supplies the leaf (the nested chain flattens into the outer one).
///
/// Fully `const`-constructible: the [children] are referenced as authored and
/// never reconstructed — each link's downstream is supplied at the element
/// layer, not by copying seeds. An empty [children] mounts the leaf directly.
class Nest extends Component implements SingleChildComponent {
  /// Creates a chain that wraps [child] with each of [children] in order (the
  /// first is outermost), optionally [key]ed. [child] is the leaf; leave it
  /// null only when placing this `Nest` inside another `Nest`, which then
  /// supplies the leaf.
  const Nest({required this.children, this.child, super.key});

  /// The wrapping seeds, outermost first. Each is placed as the parent of the
  /// next; the last wraps the leaf.
  final List<SingleChildComponent> children;

  /// The leaf subtree at the bottom of the chain. Null means "supplied by an
  /// enclosing [Nest]".
  @override
  final Component? child;

  @override
  NestElement createElement() => NestElement(this);

  @override
  @Deprecated('Use createElement instead.')
  NestElement createBranch() => createElement();
}

/// Mounted element for a [Nest]: folds the declared chain into a spine of hook
/// elements and keeps it reconciled.
///
/// Each rebuild refolds [Nest.children] into fresh internal [_NestHook]
/// carriers (innermost-out), so a change to a downstream link or the leaf
/// propagates through otherwise-identical intermediate links — the Flutter
/// `nested` behaviour, where rebuilding the chain rebuilds all of it. When the
/// `Nest` itself is reused unchanged, the parent's identical-config fast path
/// prunes the whole chain before this hook runs.
///
/// `NestElement` carries [SingleChildElementMixin] so a `Nest` used as a link in
/// an enclosing `Nest` takes its leaf from the injected downstream.
class NestElement extends Element with SingleChildElementMixin {
  /// Creates the element for [component].
  NestElement(Nest super.component);

  Element? _head;

  /// The head of the mounted chain (the outermost link's hook element, or the
  /// leaf's element when [Nest.children] is empty). Exposed for testing.
  /// Do not use in production code.
  Element? get head => _head;

  Nest get _nest => component as Nest;

  @override
  void mount(Element? parent, Object? slot) {
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
    Component acc = _leaf();
    for (var i = children.length - 1; i >= 0; i--) {
      acc = _NestHook(children[i], acc);
    }
    _head = updateChild(_head, acc, 0);
  }

  // The leaf at the bottom of this chain: the injected downstream when this
  // `Nest` is a link in an enclosing `Nest`, else the component's own child.
  Component _leaf() {
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
  void visitChildren(void Function(Element child) visitor) {
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
/// own element, and the source that element reads its injected downstream from
/// (via [SingleChildElementMixin]). This lets `Nest` supply a downstream without
/// reconstructing the user's (const) seeds.
///
/// Its key encodes the node's identity — the user key if any, else the node's
/// runtimeType — so that at a fixed chain position a same-type node reconciles
/// in place (preserving stateful state) while a type change remounts (fresh
/// state), even though every hook shares runtimeType `_NestHook`.
class _NestHook extends Component {
  _NestHook(this.node, this.injected)
    : super(key: node.key ?? ValueKey<Type>(node.runtimeType));

  final SingleChildComponent node;
  final Component injected;

  @override
  _NestHookElement createElement() => _NestHookElement(this);
}

/// Element for a [_NestHook]: mounts the node's own element as its child and
/// exposes the [injected] downstream to it. Mirroring `nested`'s injectedChild
/// setter, it forces that child to rebuild when only the downstream changed —
/// the node instance is reused across a chain rebuild, so reconciliation would
/// otherwise skip it and the new downstream would never reach the leaf.
class _NestHookElement extends Element {
  _NestHookElement(_NestHook super.component);

  Element? _child;

  _NestHook get _hookComponent => component as _NestHook;

  /// The downstream this link supplies to its wrapped node.
  Component get injected => _hookComponent.injected;

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _child = updateChild(_child, _hookComponent.node, 0);
  }

  @override
  void update(Component newComponent) {
    final old = _hookComponent;
    super.update(newComponent);
    final now = _hookComponent;
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
  void visitChildren(void Function(Element child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}

/// Legacy name for [SingleChildComponent].
@Deprecated('Use SingleChildComponent instead.')
typedef SingleChildSeed = SingleChildComponent;

/// Legacy name for [SingleChildElementMixin].
@Deprecated('Use SingleChildElementMixin instead.')
typedef SingleChildBranchMixin = SingleChildElementMixin;

/// Legacy name for [SingleChildStatelessComponent].
@Deprecated('Use SingleChildStatelessComponent instead.')
typedef SingleChildStatelessSeed = SingleChildStatelessComponent;

/// Legacy name for [SingleChildStatelessElement].
@Deprecated('Use SingleChildStatelessElement instead.')
typedef SingleChildStatelessBranch = SingleChildStatelessElement;

/// Legacy name for [SingleChildStatefulComponent].
@Deprecated('Use SingleChildStatefulComponent instead.')
typedef SingleChildStatefulSeed = SingleChildStatefulComponent;

/// Legacy name for [SingleChildStatefulElement].
@Deprecated('Use SingleChildStatefulElement instead.')
typedef SingleChildStatefulBranch = SingleChildStatefulElement;

/// Legacy name for [NestElement].
@Deprecated('Use NestElement instead.')
typedef NestBranch = NestElement;
