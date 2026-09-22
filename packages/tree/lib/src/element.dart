import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:meta/meta.dart';

import 'key.dart';
import 'build_context.dart';
import 'build_owner.dart';
import 'component.dart';

/// Mounted, persistent node in the component tree.
///
/// `Element` core is artifact-agnostic: it owns identity, lifecycle
/// (mount/update/unmount), keyed reconciliation, dirtiness, and the single
/// [performRebuild] hook. It carries no build contract — the composition layer
/// (`BuildableElement` and friends) defines the hook as re-running `build()`;
/// other elements define their own rebuild behavior.
///
/// `Element` deliberately does NOT implement [BuildContext]. The build-time
/// capability handle is a separate object
/// obtained via [context]; it throws [StateError] on use after this element
/// unmounts, so a handle held across an async gap fails loudly instead of
/// silently acting on a stale node.
abstract class Element with Diagnosticable, DiagnosticableTree {
  /// Creates an element configured by [component].
  Element(Component component) : _component = component;

  Component _component;

  /// The current [Component] configuration for this element.
  Component get component => _component;

  /// Legacy spelling for [component].
  @Deprecated('Use component instead.')
  Component get seed => component;

  /// Stable id for this mounted element; assigned at mount time via
  /// [BuildOwner.issueId] and never changes during the element's lifetime.
  late final String elementId;

  /// Legacy spelling for [elementId].
  @Deprecated('Use elementId instead.')
  String get branchId => elementId;

  /// The [Key] of the underlying [Component] config, or null if unkeyed.
  Key? get key => _component.key;

  BuildContext? _context;

  /// The capability handle for this element.
  ///
  /// This is the object the composition layer passes to `build()` and
  /// surfaces as `State.context`. It is never the element itself; after this
  /// element unmounts the handle throws [StateError] on use — except
  /// [BuildContext.mounted], which stays queryable as the staleness probe.
  BuildContext get context => _context ??= createBuildContext(this);

  // Providers (InheritedElementBase ancestors) this element currently depends
  // on. Lazily allocated — the common element depends on nothing, so it never
  // pays for the set (a Element-purity footprint tightening; the inherited-
  // propagation machinery is the one Element-bloat category the base carries,
  // so keep its cost off elements that don't use it).
  Set<InheritedElementBase>? _dependencies;

  /// Returns the nearest ancestor value provided via `InheritedComponent<T>` of
  /// exact type [T], registering this element as a dependent; null when no
  /// such ancestor exists.
  ///
  /// Pass [aspect] to scope the dependency. When the resolved provider is an
  /// `InheritedModel<T, A>`, this element is invalidated only for changes
  /// its `updateShouldNotifyDependent` reports as affecting the aspects this
  /// element asked for. Omitting [aspect] depends on the WHOLE value — the
  /// behaviour of every plain `InheritedComponent<T>` provider, and of this method
  /// before aspects existed. Passing an [aspect] to a plain provider throws
  /// [ArgumentError].
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect}) {
    final provider = _findInheritedProviderOfExactType<T>();
    if (provider == null) return null;
    provider.addDependent(this, aspect: aspect);
    (_dependencies ??= {}).add(provider);
    return provider.getValueAs<T>();
  }

  /// Legacy spelling for [dependOnInheritedValueOfExactType].
  @Deprecated('Use dependOnInheritedValueOfExactType instead.')
  T? dependOnInheritedSeedOfExactType<T extends Object>({Object? aspect}) =>
      dependOnInheritedValueOfExactType<T>(aspect: aspect);

  /// Returns the nearest ancestor value provided via `InheritedComponent<T>` of
  /// exact type [T] **without registering a dependency**; null when no such
  /// ancestor exists.
  ///
  /// The non-subscribing counterpart of [dependOnInheritedValueOfExactType]:
  /// the returned value is a snapshot — a later change to the provided value
  /// does not rebuild this element. Use it for one-shot reads (grabbing an
  /// ambient service in `State.initState`, inside an effect, during
  /// teardown); use the depend variant wherever this element must rebuild
  /// when the value changes.
  T? getInheritedValueOfExactType<T extends Object>() =>
      _findInheritedProviderOfExactType<T>()?.getValueAs<T>();

  /// Legacy spelling for [getInheritedValueOfExactType].
  @Deprecated('Use getInheritedValueOfExactType instead.')
  T? getInheritedSeedOfExactType<T extends Object>() =>
      getInheritedValueOfExactType<T>();

  // The single provider-lookup site shared by the depend/get pair: walks the
  // parent chain for the nearest provider whose exact value-type is T.
  InheritedElementBase? _findInheritedProviderOfExactType<T extends Object>() {
    Element? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is InheritedElementBase &&
          ancestor.getValueAs<T>() != null) {
        return ancestor;
      }
      ancestor = ancestor._parent;
    }
    return null;
  }

  /// Marks this element dirty so the next [BuildOwner.flush] rebuilds it.
  void markNeedsRebuild() {
    if (mounted && !_dirty) {
      _dirty = true;
      owner?.scheduleRebuildFor(this);
    }
  }

  /// Called by `InheritedElement` when a depended-on value changes.
  /// Default: delegates to [markNeedsRebuild].
  /// `StatefulElement` overrides this to also flag didChangeDependencies.
  void dependencyChanged() => markNeedsRebuild();

  /// Runs [performRebuild] when this element is mounted and dirty (or when
  /// [force] is true — the update path). Clears the dirty
  /// flag first, so a element force-rebuilt during reconciliation is skipped
  /// when the owner later drains it in the same flush.
  void rebuild({bool force = false}) {
    if (mounted && (_dirty || force)) {
      _dirty = false;
      owner!.runElementBuild(this, performRebuild);
    }
  }

  /// The single rebuild hook. `Element` core attaches no meaning to it; the
  /// composition layer defines it as re-running `build()`, and non-component
  /// elements define their own rebuild behavior.
  @protected
  void performRebuild() {}

  // --- Internal state ---

  Element? _parent;
  bool _mounted = false;
  bool _dirty = false;

  /// The [BuildOwner] this element is mounted under. Set by
  /// [BuildOwner.mountRoot] for roots and inherited from the parent in
  /// [mount].
  BuildOwner? owner;

  /// Depth from the root (root = 0). Drives the owner's depth-ordered flush.
  int depth = 0;

  /// Whether this element is currently mounted in a tree.
  bool get mounted => _mounted;

  /// Whether this element is currently marked as needing rebuild.
  bool get dirty => _dirty;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    component.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty.flag(
          name: 'mounted',
          level: DiagnosticsLevel.info,
          value: mounted,
        ),
      )
      ..add(
        DiagnosticsProperty.flag(
          name: 'dirty',
          level: DiagnosticsLevel.info,
          value: dirty,
        ),
      );
    if (mounted) {
      properties.add(
        DiagnosticsProperty.string(
          name: 'elementId',
          level: DiagnosticsLevel.info,
          value: elementId,
        ),
      );
    }
  }

  @override
  List<Diagnosticable> debugDescribeChildren() {
    final children = <Diagnosticable>[];
    visitChildren(children.add);
    return children;
  }

  /// Providers this element depends on. Exposed for testing.
  /// Do not use in production code.
  Set<Element> get dependencies => _dependencies ?? const <Element>{};

  // --- Traversal ---

  /// Calls [visitor] once for each direct child of this element, in tree
  /// order.
  ///
  /// `Element` core holds no children, so the base implementation visits
  /// nothing; subclasses that own children override this. The walk is
  /// shallow — callers recurse to traverse a subtree. The tree must not be
  /// mutated during a visit.
  void visitChildren(void Function(Element child) visitor) {}

  // --- Lifecycle ---

  /// Attaches this element into the tree under [parent] at [slot].
  @mustCallSuper
  void mount(Element? parent, Object? slot) {
    assert(
      !_mounted,
      'mount() called on already-mounted element (id=$elementId).',
    );
    _parent = parent;
    owner ??= parent?.owner;
    assert(
      owner != null,
      'mount() requires a non-null owner; call BuildOwner.mountRoot() '
      'for root elements, or mount under a parent that has an owner.',
    );
    elementId = owner!.issueId();
    _mounted = true;
    depth = (parent?.depth ?? -1) + 1;
  }

  /// Updates the config node when [Component.canUpdate] is true, then invokes the
  /// rebuild path: a config update reaches [performRebuild] with the new
  /// [component] already in place. What the hook does is layered — components
  /// re-run `build()`; non-component elements respond with their own
  /// rebuild semantics.
  ///
  /// Throws [StateError] when [Component.canUpdate] is false — in release builds
  /// too, because swapping in an incompatible config silently corrupts the
  /// element's identity.
  @mustCallSuper
  void update(Component newComponent) {
    assert(_mounted, 'update() called on unmounted element.');
    if (!Component.canUpdate(_component, newComponent)) {
      throw StateError(
        'update() called with a Component that fails canUpdate: mounted '
        '${_component.runtimeType} (key ${_component.key}) cannot be updated '
        'with ${newComponent.runtimeType} (key ${newComponent.key}); use '
        'unmount() + mount() '
        'for type/key changes.',
      );
    }
    _component = newComponent;
    rebuild(force: true);
  }

  /// Detaches this element from the tree.
  @mustCallSuper
  void unmount() {
    assert(_mounted, 'unmount() called on already-unmounted element.');
    final deps = _dependencies;
    if (deps != null) {
      for (final dep in List.of(deps)) {
        dep.removeDependent(this);
      }
    }
    _mounted = false;
    _parent = null;
  }

  /// Package-internal: called only by `InheritedElement.removeDependent`.
  void removeDependency(Element dep) {
    _dependencies?.remove(dep);
  }

  // --- Single-child reconciliation ---

  /// Reconciles [child] against [newComponent] at [slot].
  ///
  /// When an existing [child] is reconciled against an identical
  /// [newComponent] (`identical(child.component, newComponent)`), the
  /// identical-skip fast path returns it untouched. Ported
  /// from Flutter's `Element.updateChild`), the child is returned untouched: no
  /// [update], no [rebuild], no subtree cascade. A `const`-canonicalized component
  /// or a deliberately reused instance therefore prunes its whole subtree at
  /// reconcile time. The skip is identity-only by construction — it never
  /// consults [Component.operator==], so components remain free to define value
  /// equality (e.g. for wire diffing) without changing reconcile semantics.
  ///
  /// The skip is reconciliation's concern only: [update] keeps its
  /// force-rebuild semantics, so a direct `element.update(sameInstance)` still
  /// rebuilds. A provider whose value changed but whose child instance is
  /// reused invalidates its dependents through [dependencyChanged]
  /// independently of this skip; they land in the owner dirty set and rebuild
  /// when [BuildOwner.flush] drains them.
  ///
  /// Deferred obligation: Flutter still updates a skipped child's *slot* on
  /// the fast path (`updateSlotForChild`). [Element] stores no slot — position
  /// lives only in the parent's child list — so there is no slot-update element
  /// here yet. The day render elements grow slots, the skip must update the
  /// slot before returning.
  Element? updateChild(Element? child, Component? newComponent, Object? slot) {
    if (newComponent == null) {
      child?.unmount();
      return null;
    }
    if (child != null) {
      // Identical-skip fast path: an identical config skips the rebuild
      // entirely.
      if (identical(child._component, newComponent)) {
        return child;
      }
      if (Component.canUpdate(child._component, newComponent)) {
        child.update(newComponent);
        return child;
      }
      child.unmount();
    }
    final element = newComponent.createElement();
    element.mount(this, slot);
    return element;
  }

  // --- Multi-child keyed reconciliation ---

  /// Reconciles [oldChildren] against [newComponents] by key identity.
  ///
  /// Each new component is matched to an old element — keyed components by
  /// key, unkeyed components positionally by cursor — and the matched pair is
  /// reconciled through
  /// [updateChild] (Flutter's shape: `updateChildren` delegates per position),
  /// so the identical-config fast path applies uniformly to the multichild
  /// path from a single skip site. A matched-but-incompatible element
  /// (`canUpdate` false) is unmounted and replaced by [updateChild]; matched
  /// old elements left unconsumed (a keyed element whose key vanished, or
  /// unkeyed elements past the new length) are unmounted after the pass.
  List<Element> updateChildren(
    List<Element> oldChildren,
    List<Component> newComponents,
  ) {
    _childKeysUnique(newComponents);
    final Map<Key, Element> keyedOld = {};
    final List<Element> unkeyedOld = [];
    for (final element in oldChildren) {
      if (element._component.key != null) {
        keyedOld[element._component.key!] = element;
      } else {
        unkeyedOld.add(element);
      }
    }

    int unkeyedCursor = 0;
    final result = <Element>[];

    for (int i = 0; i < newComponents.length; i++) {
      final newComponent = newComponents[i];
      Element? match;
      if (newComponent.key != null) {
        match = keyedOld.remove(newComponent.key);
      } else if (unkeyedCursor < unkeyedOld.length) {
        match = unkeyedOld[unkeyedCursor++];
      }

      // Route through updateChild so the identical-skip and the
      // canUpdate-or-replace decision live in exactly one place; updateChild
      // never returns null for a non-null component, so the result is non-null.
      result.add(updateChild(match, newComponent, i)!);
    }

    for (final element in keyedOld.values) {
      element.unmount();
    }
    for (int i = unkeyedCursor; i < unkeyedOld.length; i++) {
      unkeyedOld[i].unmount();
    }

    return result;
  }

  /// Unconditional guard, release included (O(n) in the child count): a key
  /// must identify exactly ONE child of a parent. Two siblings sharing a key
  /// collapse silently in keyed reconcile — the map keeps only one, and a
  /// key-based tree lookup would find more than one. Throws [StateError]
  /// naming the offending key BEFORE any old element is touched, so a rejected
  /// list leaves the mounted tree exactly as it was. Unkeyed children are
  /// matched positionally and are exempt.
  void _childKeysUnique(List<Component> components) {
    final seen = <Key>{};
    for (final component in components) {
      final key = component.key;
      if (key != null && !seen.add(key)) {
        throw StateError(
          'Duplicate child key "$key" among the children of one parent. A key '
          'identifies exactly one child — it is the reconciliation identity, '
          'and a key-based lookup expects one element per key. Give each '
          'sibling a distinct key (or leave them unkeyed for positional '
          'matching).',
        );
      }
    }
  }
}

/// Package-internal: returns [element]'s parent for owner-level ancestry checks
/// without exposing mutable parent state.
@internal
Element? debugParentOf(Element element) => element._parent;

/// Package-internal bridge. Defined alongside [Element] so that
/// [Element._dependencies] can be typed `Set<InheritedElementBase>` without
/// importing `inherited.dart` (which would create a problematic cross-library
/// private-access cycle). Do not use or extend directly — use
/// `InheritedComponent`/`InheritedElement` instead.
@internal
abstract class InheritedElementBase extends Element {
  /// Forwards [component] to [Element].
  InheritedElementBase(super.component);

  /// Returns this element's wrapped value as [T] if its exact value-type
  /// equals [T]; null otherwise. Used by the parent-walk in
  /// [Element.dependOnInheritedValueOfExactType].
  T? getValueAs<T extends Object>();

  /// Registers [element] as a dependent. Idempotent (set-add).
  ///
  /// [aspect] scopes the dependency for an aspect-aware provider
  /// (`InheritedModelElement`). A provider with no aspect vocabulary rejects a
  /// non-null [aspect] with [ArgumentError].
  void addDependent(Element element, {Object? aspect});

  /// Removes [element] from this element's dependent set and clears the
  /// corresponding back-link in [element]'s dependency set.
  void removeDependent(Element element);
}

/// Legacy name for [Element].
@Deprecated('Use Element instead.')
typedef Branch = Element;

/// Legacy name for [InheritedElementBase].
@Deprecated('Use InheritedElementBase instead.')
typedef InheritedBranchBase = InheritedElementBase;
