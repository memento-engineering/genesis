import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

/// Creates the value a [Provider] OWNS, from ambient tree state.
///
/// Runs exactly once per mount, inside `initState`. Lookups through [TreeContext]
/// here must be dependency-free — use the [ProviderTreeContext.read] verb (the
/// substrate asserts on a build-binding `dependOn` lookup in `initState`). This
/// is how a provider constructs its value from ambient configuration provided
/// by an ancestor.
typedef ProviderCreate<T extends Object> = T Function(TreeContext context);

/// Disposes a value a [Provider] CREATED.
///
/// Never called for an adopted ([Provider.value]) instance — ownership follows
/// construction (`docs/STYLE.md` rule 2): the tree disposes only what the tree
/// created. Runs only after the provider's subtree is FULLY unmounted, so a
/// descendant's teardown read (`context.read` from `State.dispose` — the
/// substrate-endorsed last get-lookup) observes a live value, and a [Nest]
/// chain disposes inner-before-outer (reverse creation order — a value built
/// from an ancestor-provided one goes down before its dependency).
typedef ProviderDispose<T extends Object> = void Function(T value);

/// Derives an owned [R] from one ambient [T] and the nullable previous [R].
typedef ProxyProviderUpdate<T extends Object, R extends Object> =
    R Function(TreeContext context, T value, R? previous);

/// Derives an owned [R] from two ambient values and the nullable previous [R].
typedef ProxyProvider2Update<
  T1 extends Object,
  T2 extends Object,
  R extends Object
> = R Function(TreeContext context, T1 value1, T2 value2, R? previous);

/// Derives an owned [R] from three ambient values and the nullable previous
/// [R].
typedef ProxyProvider3Update<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  R extends Object
> =
    R Function(
      TreeContext context,
      T1 value1,
      T2 value2,
      T3 value3,
      R? previous,
    );

/// Derives an owned [R] from four ambient values and the nullable previous
/// [R].
typedef ProxyProvider4Update<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  R extends Object
> =
    R Function(
      TreeContext context,
      T1 value1,
      T2 value2,
      T3 value3,
      T4 value4,
      R? previous,
    );

/// Derives an owned [R] from five ambient values and the nullable previous
/// [R].
typedef ProxyProvider5Update<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  T5 extends Object,
  R extends Object
> =
    R Function(
      TreeContext context,
      T1 value1,
      T2 value2,
      T3 value3,
      T4 value4,
      T5 value5,
      R? previous,
    );

/// Derives an owned [R] from six ambient values and the nullable previous [R].
typedef ProxyProvider6Update<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  T5 extends Object,
  T6 extends Object,
  R extends Object
> =
    R Function(
      TreeContext context,
      T1 value1,
      T2 value2,
      T3 value3,
      T4 value4,
      T5 value5,
      T6 value6,
      R? previous,
    );

/// Shared provider configuration consumed by the one ownership state/branch
/// path. Adopted [Provider.value] instances are the only values outside that
/// path.
abstract class _ProviderSeedBase<R extends Object>
    extends SingleChildStatefulSeed {
  const _ProviderSeedBase({super.child, super.key});

  ProviderCreate<R>? get _providerCreate;
  ProviderDispose<R>? get _providerDispose;
  bool get _treeOwnsValues;

  @override
  SingleChildStatefulBranch createBranch() => _ProviderBranch(this);
}

/// A MOUNTED SEED providing an ambient value of type [T] to its subtree.
///
/// `Provider` sits on the single-child ancestry ([SingleChildStatefulSeed]),
/// so it composes both ways:
///
/// - standalone, wrapping its own `child:`;
/// - as a link in a [Nest] — the multi-provider sugar; there is deliberately
///   no dedicated wrapper type:
///
/// ```dart
/// Nest(
///   children: [
///     Provider<Settings>(create: (context) => Settings(...)),
///     Provider<Client>(create: (context) => Client(...)),
///   ],
///   child: Application(),
/// )
/// ```
///
/// **Lifecycle.** A create-provider runs [ProviderCreate] exactly once per
/// mount, in `initState`; the tree owns the created value and disposes it at
/// unmount through [ProviderDispose] — AFTER the subtree is fully down, so
/// teardown reads see a live value and a [Nest] chain disposes
/// inner-before-outer. A [Provider.value] provider ADOPTS an
/// instance held by another owner and never disposes it (`docs/STYLE.md` rule
/// 2). The build is pure: it projects the value over the child as an
/// [InheritedSeed] and does nothing else (`docs/STYLE.md` rule 1).
///
/// **Failed mount.** A `create` that throws fails the whole mount, and the
/// unwind strands no owned value: every provider whose own mount encloses the
/// failure — the failing provider itself, each earlier link of the same
/// [Nest] chain, every provider ancestor — disposes what it already created,
/// in reverse creation order, before the error rethrows (see
/// [_ProviderBranch] for the mechanism and its exact extent).
///
/// **Reconcile.** Same runtimeType + key updates in place: a `.value` update
/// propagates to dependents through [InheritedSeed.updateShouldNotify]; a
/// create-provider never re-runs `create` on update. A type or key change is
/// unmount + remount by substrate rules — the provider's kind (create vs
/// `.value`) is therefore fixed for the life of a mounted branch.
///
/// **Availability.** Descendants bind with [ProviderTreeContext.watch] —
/// nullable always; absence is a designed posture (`docs/STYLE.md` rules 3-4).
/// Mount and unmount are announced to the enclosing [ProviderScope] so
/// availability notification is bidirectional; delivery is deferred past the
/// announcing flush pass (see [ProviderScope] for the scheduling contract).
final class Provider<T extends Object> extends _ProviderSeedBase<T> {
  /// A provider whose value the TREE creates and owns: [create] runs once per
  /// mount and [dispose] (if any) runs at unmount with the created value.
  ///
  /// Never pass a pre-built instance through [create] — that falsely assigns
  /// ownership to the tree (`docs/STYLE.md` rule 2); adopt it with
  /// [Provider.value] instead.
  const Provider({
    required ProviderCreate<T> create,
    ProviderDispose<T>? dispose,
    super.child,
    super.key,
  }) : _create = create,
       _dispose = dispose,
       _value = null;

  /// A provider ADOPTING [value] — an instance held by another owner. The tree
  /// never disposes it; a changed value on reconcile propagates to dependents.
  const Provider.value(T value, {super.child, super.key})
    : _value = value,
      _create = null,
      _dispose = null;

  final ProviderCreate<T>? _create;
  final ProviderDispose<T>? _dispose;
  final T? _value;

  @override
  ProviderCreate<T>? get _providerCreate => _create;

  @override
  ProviderDispose<T>? get _providerDispose => _dispose;

  @override
  bool get _treeOwnsValues => _create != null;

  @override
  SingleChildState<Provider<T>> createState() => _ProviderState<T>();
}

/// Shared lifecycle configuration for every ProxyProvider arity.
abstract class _ProxyProviderBase<R extends Object>
    extends _ProviderSeedBase<R> {
  const _ProxyProviderBase({
    ProviderCreate<R>? create,
    ProviderDispose<R>? dispose,
    super.child,
    super.key,
  }) : _create = create,
       _dispose = dispose;

  final ProviderCreate<R>? _create;
  final ProviderDispose<R>? _dispose;

  @override
  ProviderCreate<R>? get _providerCreate => _create;

  @override
  ProviderDispose<R>? get _providerDispose => _dispose;

  @override
  bool get _treeOwnsValues => true;

  /// Watches every declared input, then returns null when any is absent or
  /// invokes this arity's typed callback with all resolved values.
  R? _derive(TreeContext context, R? previous);

  @override
  SingleChildState<_ProxyProviderBase<R>> createState() =>
      _ProxyProviderState<R>();
}

/// Provides an owned [R] derived from an ambient [T].
///
/// Every build watches [T]. Once it resolves, [update] receives the current
/// value and the previous [R], and its result is projected to descendants.
/// The optional [create] runs once at mount and seeds the first update's
/// `previous`; without it, the first update receives null. Every distinct
/// created or updated [R] is tree-owned and disposed when replaced or after
/// descendant teardown. There is deliberately no `.value` form: adoption
/// remains [Provider.value].
final class ProxyProvider<T extends Object, R extends Object>
    extends _ProxyProviderBase<R> {
  /// Creates a one-input proxy provider.
  const ProxyProvider({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] from [T] and the nullable previous [R].
  final ProxyProviderUpdate<T, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    final value = context.watch<T>();
    if (value == null) return null;
    return update(context, value, previous);
  }
}

/// Provides an owned [R] derived from two ambient values.
final class ProxyProvider2<
  T1 extends Object,
  T2 extends Object,
  R extends Object
>
    extends _ProxyProviderBase<R> {
  /// Creates a two-input proxy provider.
  const ProxyProvider2({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] after both dependencies resolve.
  final ProxyProvider2Update<T1, T2, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    final value1 = context.watch<T1>();
    final value2 = context.watch<T2>();
    if (value1 == null || value2 == null) return null;
    return update(context, value1, value2, previous);
  }
}

/// Provides an owned [R] derived from three ambient values.
final class ProxyProvider3<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  R extends Object
>
    extends _ProxyProviderBase<R> {
  /// Creates a three-input proxy provider.
  const ProxyProvider3({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] after all three dependencies resolve.
  final ProxyProvider3Update<T1, T2, T3, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    final value1 = context.watch<T1>();
    final value2 = context.watch<T2>();
    final value3 = context.watch<T3>();
    if (value1 == null || value2 == null || value3 == null) return null;
    return update(context, value1, value2, value3, previous);
  }
}

/// Provides an owned [R] derived from four ambient values.
final class ProxyProvider4<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  R extends Object
>
    extends _ProxyProviderBase<R> {
  /// Creates a four-input proxy provider.
  const ProxyProvider4({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] after all four dependencies resolve.
  final ProxyProvider4Update<T1, T2, T3, T4, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    final value1 = context.watch<T1>();
    final value2 = context.watch<T2>();
    final value3 = context.watch<T3>();
    final value4 = context.watch<T4>();
    if (value1 == null || value2 == null || value3 == null || value4 == null) {
      return null;
    }
    return update(context, value1, value2, value3, value4, previous);
  }
}

/// Provides an owned [R] derived from five ambient values.
final class ProxyProvider5<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  T5 extends Object,
  R extends Object
>
    extends _ProxyProviderBase<R> {
  /// Creates a five-input proxy provider.
  const ProxyProvider5({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] after all five dependencies resolve.
  final ProxyProvider5Update<T1, T2, T3, T4, T5, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    final value1 = context.watch<T1>();
    final value2 = context.watch<T2>();
    final value3 = context.watch<T3>();
    final value4 = context.watch<T4>();
    final value5 = context.watch<T5>();
    if (value1 == null ||
        value2 == null ||
        value3 == null ||
        value4 == null ||
        value5 == null) {
      return null;
    }
    return update(context, value1, value2, value3, value4, value5, previous);
  }
}

/// Provides an owned [R] derived from six ambient values.
final class ProxyProvider6<
  T1 extends Object,
  T2 extends Object,
  T3 extends Object,
  T4 extends Object,
  T5 extends Object,
  T6 extends Object,
  R extends Object
>
    extends _ProxyProviderBase<R> {
  /// Creates a six-input proxy provider.
  const ProxyProvider6({
    super.create,
    required this.update,
    super.dispose,
    super.child,
    super.key,
  });

  /// Derives the next [R] after all six dependencies resolve.
  final ProxyProvider6Update<T1, T2, T3, T4, T5, T6, R> update;

  @override
  R? _derive(TreeContext context, R? previous) {
    // Resolve every dependency before checking for a miss. An early return
    // would leave later absent types unregistered with ProviderScope.
    final value1 = context.watch<T1>();
    final value2 = context.watch<T2>();
    final value3 = context.watch<T3>();
    final value4 = context.watch<T4>();
    final value5 = context.watch<T5>();
    final value6 = context.watch<T6>();
    if (value1 == null ||
        value2 == null ||
        value3 == null ||
        value4 == null ||
        value5 == null ||
        value6 == null) {
      return null;
    }
    return update(
      context,
      value1,
      value2,
      value3,
      value4,
      value5,
      value6,
      previous,
    );
  }
}

/// The AVAILABILITY REGISTRY — one per tree, near the tree root.
///
/// It owns ONLY a pending-dependents-by-type map, and exists because the
/// substrate cannot register a dependency on a branch that does not exist:
/// `dependOnInheritedSeedOfExactType` returns null on a miss BEFORE any
/// dependent is added, so an absent [Provider] would otherwise leave no edge
/// to notify when it mounts.
///
/// [ProviderTreeContext.watch] resolves through the normal inherited ancestor
/// walk (nearest provider shadows); on a MISS it registers the calling branch
/// here, keyed by the missed type. A [Provider] announces its mount and
/// unmount to this scope, and the scope notifies the affected dependents
/// (`dependencyChanged` through the owner's rebuild scheduling — never
/// re-entering a build).
///
/// **Scheduling.** A provider mounts and unmounts MID-FLUSH (inside some
/// ancestor's rebuild), and the substrate forbids re-dirtying a branch that
/// was already built in the in-progress flush pass
/// (`TreeOwner.scheduleRebuildFor`). Notification is therefore DEFERRED: the
/// registry queues the affected dependents and delivers `dependencyChanged`
/// from a microtask, after the current pass has drained. The marked branches
/// ride the owner's next flush (the kernel schedules one off the
/// `onNeedsFlush` edge; tests pump the microtask queue and flush again).
///
/// **What each direction observably does on THIS substrate.** genesis_tree
/// has no reparenting, so a live dependent of a provider is always a
/// DESCENDANT of it and unmounts with it. Consequently: the mount-side drain
/// of pending dependents is the load-bearing direction (a parked watcher
/// rebuilds and re-resolves — still null when the new provider is not its
/// ancestor, the value when a remount placed it under one); the unmount-side
/// ping is contract-mandated bidirectional notification whose recipients are,
/// today, always torn down with the provider before delivery — a surviving
/// dependent (should reparenting ever exist) would rebuild, observe the null
/// posture, and re-register pending through its own watch miss. Value
/// transitions across a provider boundary otherwise ride unmount + remount of
/// the dependent subtree by ordinary substrate reconcile rules.
final class ProviderScope extends SingleChildStatefulSeed {
  /// Creates the registry over [child] (null when placed in a [Nest]).
  const ProviderScope({super.child, super.key});

  @override
  SingleChildState<ProviderScope> createState() => _ProviderScopeState();
}

/// Adds nullable provider lookup verbs to [TreeContext] (ADR-0008 D3/D-H —
/// two verbs, one lookup system).
extension ProviderTreeContext on TreeContext {
  /// The build-time BINDING verb: the nearest [T], registering the dependency
  /// edge UNCONDITIONALLY — with the provider's branch on a hit, or with the
  /// enclosing [ProviderScope]'s pending map on a miss.
  ///
  /// Nullable ALWAYS, and deliberately without a throwing variant:
  /// unavailability is a designed posture (`docs/STYLE.md` rule 3). The
  /// notification is bidirectional — mount and unmount announcements both
  /// reach the registered dependents — and DEFERRED: delivery is a microtask
  /// after the flush pass the provider (un)mounted in, so the rebuild lands
  /// in the owner's next flush (see [ProviderScope] for scheduling and for
  /// what each direction observably does on this substrate).
  ///
  /// Use [read] for a non-binding snapshot lookup from an effect path.
  T? watch<T extends Object>() {
    final value = dependOnInheritedSeedOfExactType<T>();
    if (value != null) return value;
    // MISS: the walk found no provider, so no branch holds the edge. Park the
    // registration with the availability registry. The registration rides the
    // substrate's own addDependent path (see _RegistryBranch): the registry
    // branch never notifies (its value is scope-lifetime stable), and the
    // dependency edge auto-releases when this branch unmounts.
    final registry = getInheritedSeedOfExactType<AvailabilityRegistry>();
    // Debug guard, release behavior unchanged (return null): a scope-less
    // miss is almost always a composition mistake — the registration cannot
    // park anywhere, so the branch would never learn when a Provider<T>
    // mounts. Applications should mount the scope near the tree root.
    assert(
      registry != null,
      'watch<$T>() missed with no ProviderScope ancestor: there is no '
      'availability registry to park the pending registration with, so this '
      'branch can never be notified when a Provider<$T> mounts. Mount a '
      'ProviderScope near the tree root (above every watching branch), or '
      'use read<$T>() if a one-shot snapshot is all that is needed.',
    );
    if (registry != null) {
      registry._registering = T;
      try {
        dependOnInheritedSeedOfExactType<AvailabilityRegistry>();
      } finally {
        registry._registering = null;
      }
    }
    return null;
  }

  /// The effect-path SNAPSHOT verb: the nearest [T] without registering any
  /// dependency — neither live nor pending. A later change, mount, or unmount
  /// of the provider does not rebuild this branch.
  T? read<T extends Object>() => getInheritedSeedOfExactType<T>();
}

// --- Provider internals -----------------------------------------------------

/// Owns one provider-created value and its mount-captured disposal policy.
///
/// Both Provider and every ProxyProvider arity use this owner. Adopted
/// Provider.value instances never enter it. Replacement installs the new
/// value first, then disposes a distinct previous value; identity retention
/// is not a replacement. Final disposal clears first, so every value is
/// disposed at most once even when a callback throws.
final class _ProviderValueOwner<R extends Object> {
  _ProviderValueOwner(this._disposeValue);

  final ProviderDispose<R>? _disposeValue;
  R? _value;

  R? get value => _value;

  void _replace(R value) {
    final previous = _value;
    if (identical(previous, value)) return;
    _value = value;
    if (previous != null) _disposeValue?.call(previous);
  }

  void _dispose() {
    final value = _value;
    _value = null;
    if (value != null) _disposeValue?.call(value);
  }
}

/// The one ownership/projection state shared by Provider and ProxyProvider.
abstract class _ProviderStateBase<
  S extends _ProviderSeedBase<R>,
  R extends Object
>
    extends SingleChildState<S> {
  _ProviderValueOwner<R>? _owner;

  @override
  void initState() {
    if (!seed._treeOwnsValues) return;
    final owner = _owner = _ProviderValueOwner<R>(seed._providerDispose);
    final create = seed._providerCreate;
    if (create != null) owner._replace(create(context));
  }

  /// Resolves the value to project for this build, or null while a proxy is
  /// still missing at least one dependency.
  R? valueForBuild(TreeContext context);

  /// The failed-mount unwind (see [_ProviderBranch]). The same owner later
  /// carried by [_ProviderInherited] makes this single-shot.
  void _disposeOwnedForFailedMount() => _owner?._dispose();

  /// Final-disposal fallback for a proxy whose dependencies never resolved,
  /// so it never built the [_ProviderInherited] that normally disposes after
  /// descendant teardown. For every projected value this is a no-op because
  /// that inherited branch has already cleared the same stable owner.
  void _disposeOwnedAfterSubtree() => _owner?._dispose();

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final value = valueForBuild(context);
    if (value == null) return child;
    return _ProviderInherited<R>(value: value, child: child, owner: _owner);
  }
}

final class _ProviderState<T extends Object>
    extends _ProviderStateBase<Provider<T>, T> {
  @override
  T? valueForBuild(TreeContext context) {
    // Reading seed._value (not a cached copy) propagates a `.value` update.
    // The bidirectional kind guard is deliberately loud in every build mode,
    // preserving the release-mode invariant doctrine across the shared base.
    final adopted = seed._value;
    final owned = _owner?.value;
    if (adopted != null && owned != null) {
      throw StateError(
        'Provider<$T> reconciled from create: into .value — the provider kind '
        'is fixed for the life of a mounted branch (same runtimeType + key '
        'updates in place). Change the type or key to remount instead.',
      );
    }
    final value = adopted ?? owned;
    if (value == null) {
      throw StateError(
        'Provider<$T> reconciled from .value into create: — the provider kind '
        'is fixed for the life of a mounted branch (same runtimeType + key '
        'updates in place). Change the type or key to remount instead.',
      );
    }
    return value;
  }
}

final class _ProxyProviderState<R extends Object>
    extends _ProviderStateBase<_ProxyProviderBase<R>, R> {
  @override
  R? valueForBuild(TreeContext context) {
    final owner = _owner!;
    final value = seed._derive(context, owner.value);
    if (value == null) return null;
    owner._replace(value);
    return owner.value;
  }
}

/// The provider's branch: a [SingleChildStatefulBranch] that additionally
/// carries the FAILED-MOUNT unwind.
///
/// **Substrate unwind semantics** (genesis_tree, investigated at 0.2.0): when
/// a mount throws mid-reconcile, `updateChild` propagates the error BEFORE the
/// caller's child-slot assignment, at every level of the failing spine. Every
/// branch mounted within the failed reconcile call is left orphaned — still
/// `mounted == true`, unreachable from the root, its `unmount()` never to be
/// called. For providers that means the disposal site
/// ([_ProviderInheritedBranch.unmount]) is unreachable: an owned value created
/// before the failure would be STRANDED, never disposed.
///
/// The unwind therefore rides the exception's own propagation: the mount-time
/// [performRebuild] frame of a provider encloses its `create` call AND the
/// mount of its entire subtree, so catching there and disposing the owned
/// value covers (a) the failing provider itself (its `create` threw — nothing
/// created, nothing to do), (b) every earlier link of the same [Nest] chain
/// (chain links nest, so each earlier "sibling" is a structural ancestor of
/// the failure — they dispose innermost-first, reverse creation order, the old
/// ProviderScope contract), and (c) any provider ancestor elsewhere up the
/// spine. The error then rethrows unchanged.
///
/// Known extent: a provider subtree that fully mounted under a NON-provider
/// multi-child container before a LATER sibling of that container failed is
/// orphaned by an assignment skipped ABOVE any provider frame; no provider
/// code is on that stack, so its disposal is out of this seam's reach. The
/// multi-provider composition surface is [Nest] (which nests, and is fully
/// covered), so that shape has no production author today.
final class _ProviderBranch extends SingleChildStatefulBranch {
  _ProviderBranch(_ProviderSeedBase<Object> super.seed);

  /// True until the first (mount-pass) build completes or fails. Rebuilds of
  /// an ATTACHED provider must not run the unwind: a failure there leaves the
  /// branch attached, its value live, and its normal unmount disposal intact.
  bool _mountBuild = true;

  @override
  void performRebuild() {
    if (!_mountBuild) return super.performRebuild();
    _mountBuild = false;
    try {
      super.performRebuild();
    } catch (error, stackTrace) {
      (state as _ProviderStateBase)._disposeOwnedForFailedMount();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  void unmount() {
    super.unmount();
    (state as _ProviderStateBase)._disposeOwnedAfterSubtree();
  }
}

/// The provider's projection over its child: a plain [InheritedSeed] whose
/// branch additionally announces mount/unmount to the availability registry.
final class _ProviderInherited<T extends Object> extends InheritedSeed<T> {
  const _ProviderInherited({
    required super.value,
    required super.child,
    required this.owner,
  });

  /// The stable owner whose disposal policy was captured at mount. Null only
  /// for an adopted Provider.value instance.
  final _ProviderValueOwner<T>? owner;

  @override
  InheritedBranch<T> createBranch() => _ProviderInheritedBranch<T>(this);
}

final class _ProviderInheritedBranch<T extends Object>
    extends InheritedBranch<T> {
  _ProviderInheritedBranch(_ProviderInherited<T> super.seed);

  /// The registry captured at mount — the unmount announcement must not
  /// re-walk a tree that is already coming down.
  AvailabilityRegistry? _registry;

  /// Live dependents, mirrored through the addDependent/removeDependent
  /// chokepoints (the base class set is a test-only surface).
  final Set<Branch> _live = {};

  @override
  void addDependent(Branch branch, {Object? aspect}) {
    // Forward first: a plain provider rejects non-null aspects. Mirroring the
    // branch before that rejection would leave a phantom live dependent.
    super.addDependent(branch, aspect: aspect);
    _live.add(branch);
  }

  @override
  void removeDependent(Branch branch) {
    _live.remove(branch);
    super.removeDependent(branch);
  }

  @override
  void mount(Branch? parent, Object? slot) {
    // super.mount reconciles the child subtree first: descendants that watch
    // this type register live against THIS branch (it is mounted before they
    // build); only then are the scope's parked dependents notified.
    super.mount(parent, slot);
    final registry = _registry =
        getInheritedSeedOfExactType<AvailabilityRegistry>();
    registry?.providerMounted(T);
  }

  @override
  void unmount() {
    // Announce BEFORE the subtree comes down. Delivery is deferred (see
    // AvailabilityRegistry): by the time the notification microtask runs, a
    // dependent that unmounted with this subtree — on this no-reparent
    // substrate, all of them — is skipped by its own `mounted` guard; a
    // surviving one would rebuild, observe the null posture, and re-register
    // pending through its own watch miss.
    _registry?.providerUnmounted(T, List.of(_live));
    _live.clear();
    final owner = (seed as _ProviderInherited<T>).owner;
    super.unmount();
    // Dispose an OWNED value only now, with the subtree fully down: a
    // descendant's teardown read (`context.read` from `State.dispose`) saw a
    // live value, and across a Nest chain this branch's subtree contained
    // every inner provider — disposal therefore runs inner-before-outer,
    // reverse creation order (an inner value built from an outer one goes
    // down before its dependency).
    owner?._dispose();
  }
}

// --- ProviderScope internals ------------------------------------------------

final class _ProviderScopeState extends SingleChildState<ProviderScope> {
  /// The pending-dependents-by-type map — the scope's WHOLE state. Owned by
  /// the state so it survives reconcile; shared with providers and watchers
  /// as a scope-lifetime-stable inherited value (identity-equal across
  /// rebuilds, so InheritedSeed.updateShouldNotify never fires for it).
  final AvailabilityRegistry _registry = AvailabilityRegistry();

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      _RegistrySeed(value: _registry, child: child);
}

final class _RegistrySeed extends InheritedSeed<AvailabilityRegistry> {
  const _RegistrySeed({required super.value, required super.child});

  @override
  InheritedBranch<AvailabilityRegistry> createBranch() => _RegistryBranch(this);
}

/// The registry's branch: the substrate's addDependent path doubles as the
/// pending-registration chokepoint. A watcher that misses depends on THIS
/// branch (see [ProviderTreeContext.watch]); the interception below files it
/// under the missed type, and the substrate's unmount bookkeeping calls
/// [removeDependent], auto-releasing the parked registration.
final class _RegistryBranch extends InheritedBranch<AvailabilityRegistry> {
  _RegistryBranch(_RegistrySeed super.seed);

  @override
  void addDependent(Branch branch, {Object? aspect}) {
    // Forward first so a rejected aspect cannot park a pending registration
    // without a corresponding dependency edge in the substrate.
    super.addDependent(branch, aspect: aspect);
    final type = value._registering;
    if (type != null) value._addPending(type, branch);
  }

  @override
  void removeDependent(Branch branch) {
    value._dropPending(branch);
    super.removeDependent(branch);
  }
}

/// The pending-dependents-by-type map ([ProviderScope]'s only possession).
///
/// Public ONLY as a test seam (`@visibleForTesting`): the unmount-side
/// notification has no observable end-to-end effect on this no-reparent
/// substrate (every live dependent of an unmounting provider is a descendant
/// and unmounts with it), so its receive-side contract behavior is pinned by
/// direct unit tests against this class, and the provider branch's transmit
/// side through [debugNotifying]. Production code composes [ProviderScope]
/// and never names the registry.
///
/// **Release semantics.** A parked registration (per branch, per type,
/// idempotent) is released by exactly three events:
///
/// 1. **Drain** — a [Provider] mount of the type removes the WHOLE bucket
///    ([providerMounted]); recipients that still miss re-file through their
///    own rebuild's watch miss.
/// 2. **Delivery consumes** — any notification delivered to a branch first
///    drops ALL of that branch's parked registrations (every type): the
///    rebuild the ping triggers re-files the branch's CURRENT interests, so a
///    type the branch stopped watching does not linger past its next
///    notification.
/// 3. **Unmount** — the substrate's own dependency release
///    ([_RegistryBranch.removeDependent], riding the registry-branch edge the
///    watch miss registered) drops the branch from every bucket.
///
/// A mounted branch that rebuilds WITHOUT issuing any watch keeps its prior
/// registrations until the next of these events — there is no substrate hook
/// on a hook-free rebuild — which is bounded (at most one entry per type, all
/// for live branches) and self-corrects at the branch's next ping or unmount.
@visibleForTesting
final class AvailabilityRegistry {
  final Map<Type, Set<Branch>> _pending = {};

  /// Branches queued for a deferred [Branch.dependencyChanged] — provider
  /// (un)mount announcements land here mid-flush and are delivered from a
  /// microtask, after the in-progress pass has drained. Delivering
  /// synchronously would re-dirty a branch the current flush pass already
  /// built, which the substrate forbids (`TreeOwner.scheduleRebuildFor`).
  final Set<Branch> _notifying = {};
  bool _deliveryScheduled = false;

  /// Set by [ProviderTreeContext.watch] around its registry-dependency call so
  /// [_RegistryBranch.addDependent] knows which missed type to file the
  /// dependent under (the capability handle deliberately never exposes its
  /// branch; the substrate's own dependency path is the one place the branch
  /// surfaces).
  Type? _registering;

  void _addPending(Type type, Branch dependent) =>
      (_pending[type] ??= {}).add(dependent);

  /// Drops [dependent] from EVERY bucket — the shared release chokepoint for
  /// rules 2 (delivery consumes) and 3 (unmount, via
  /// [_RegistryBranch.removeDependent]) of the release semantics.
  void _dropPending(Branch dependent) {
    for (final waiting in _pending.values) {
      waiting.remove(dependent);
    }
  }

  /// Queues [dependents] for notification and schedules one delivery
  /// microtask. Delivery guards on [Branch.mounted]: a branch that unmounted
  /// between announcement and delivery is skipped, not retained.
  void _notifyDeferred(Iterable<Branch> dependents) {
    _notifying.addAll(dependents);
    if (_deliveryScheduled || _notifying.isEmpty) return;
    _deliveryScheduled = true;
    scheduleMicrotask(() {
      // Reset FIRST — fail-closed: even if a dependent throws below, a later
      // announcement schedules a fresh delivery instead of wedging behind a
      // stuck flag.
      _deliveryScheduled = false;
      final batch = List.of(_notifying);
      _notifying.clear();
      Object? firstError;
      StackTrace? firstStackTrace;
      for (final dependent in batch) {
        // Delivery CONSUMES the recipient's parked registrations (all types,
        // release semantics rule 2): the rebuild this ping triggers re-files
        // the branch's current interests through its own watch misses, so a
        // stale interest cannot outlive the branch's next notification.
        _dropPending(dependent);
        if (!dependent.mounted) continue;
        try {
          dependent.dependencyChanged();
        } catch (error, stackTrace) {
          // Exception-isolate the batch: one throwing dependent must not
          // swallow the remaining notifications. The first failure is
          // rethrown after the batch drains, so it still reaches the zone's
          // error handler — isolated, never silenced.
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
    });
  }

  /// A [Provider] of [type] mounted: drain its pending dependents and notify
  /// each through [Branch.dependencyChanged] — mark-needs-rebuild through the
  /// owner, DEFERRED past the flush pass the mount happened in. A notified
  /// dependent rebuilds in the owner's next flush; one that now resolves the
  /// value registers live with the provider's branch (the migration), one
  /// that still misses re-registers pending on its own rebuild.
  void providerMounted(Type type) {
    final waiting = _pending.remove(type);
    if (waiting == null) return;
    _notifyDeferred(waiting);
  }

  /// A [Provider] of [type] unmounted: its live [dependents] are notified
  /// (deferred, like the mount side). They are deliberately NOT re-parked
  /// here: a dependent that unmounts with the provider's subtree — on this
  /// no-reparent substrate, all of them — must not be retained by the
  /// registry, and a surviving one re-registers pending through its own
  /// rebuild's watch miss, which rides the [_RegistryBranch] dependency path
  /// that IS released on unmount.
  void providerUnmounted(Type type, Iterable<Branch> dependents) {
    _notifyDeferred(dependents);
  }

  /// The pending dependents parked under [type] — a read-only test probe
  /// (leak regressions assert no unmounted branch is ever retained here).
  @visibleForTesting
  Set<Branch> debugPendingOf(Type type) =>
      Set.unmodifiable(_pending[type] ?? const <Branch>{});

  /// The branches queued for the next delivery microtask — a read-only test
  /// probe. Pins the TRANSMIT side of the unmount announcement end-to-end:
  /// the provider branch's mirrored live-dependent set has no other
  /// observable outlet on this no-reparent substrate (every recipient is
  /// down before delivery), so tests read the queue between the announcing
  /// flush and the delivery microtask.
  @visibleForTesting
  Set<Branch> get debugNotifying => Set.unmodifiable(_notifying);
}
