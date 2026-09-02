/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'branch.dart';
import 'seed.dart';

/// Provides an ambient value of type [T] to all descendants in the tree —
/// the InheritedWidget analogue.
///
/// Usage:
///   `InheritedSeed<String>(value: 'hello', child: MySeed())`
///
/// Descendants subscribe with
///   `context.dependOnInheritedSeedOfExactType<String>()`
/// or take a dependency-free snapshot with
///   `context.getInheritedSeedOfExactType<String>()`.
///
/// Every dependent of an `InheritedSeed` is invalidated whenever
/// [updateShouldNotify] is true. When dependents care about DIFFERENT parts
/// of one value and should not rebuild for each other's changes, use
/// [InheritedModelSeed] instead: it scopes each dependency to an aspect.
class InheritedSeed<T extends Object> extends Seed {
  /// Creates a provider of [value] over [child].
  const InheritedSeed({required this.value, required this.child, super.key});

  /// The provided value.
  final T value;

  /// The subtree within which [value] is visible.
  final Seed child;

  /// Returns true when [oldSeed]'s value differs from the new [value].
  /// Subclasses may override for custom equality.
  bool updateShouldNotify(InheritedSeed<T> oldSeed) => value != oldSeed.value;

  @override
  InheritedBranch<T> createBranch() => InheritedBranch<T>(this);
}

/// Mounted branch for [InheritedSeed]. Owns the dependent set, reconciles the
/// single child via the rebuild hook, and invalidates dependents through
/// [Branch.dependencyChanged] when the value changes.
class InheritedBranch<T extends Object> extends InheritedBranchBase {
  /// Creates the branch for [seed].
  InheritedBranch(InheritedSeed<T> super.seed);

  final Set<Branch> _dependents = {};
  Branch? _child;

  InheritedSeed<T> get _typed => seed as InheritedSeed<T>;

  /// The currently provided value.
  T get value => _typed.value;

  // --- InheritedBranchBase ---

  @override
  U? getValueAs<U extends Object>() => T == U ? value as U : null;

  @override
  void addDependent(Branch branch, {Object? aspect}) {
    if (aspect != null) {
      throw ArgumentError.value(
        aspect,
        'aspect',
        'InheritedSeed<$T> provides no aspects — an aspect-scoped dependency '
            'needs an InheritedModelSeed<$T, A> provider. Depend without an '
            'aspect, or provide the value with an InheritedModelSeed.',
      );
    }
    _dependents.add(branch);
  }

  @override
  void removeDependent(Branch branch) {
    if (_dependents.remove(branch)) {
      branch.removeDependency(this);
    }
  }

  /// Dependents registered via dependOnInheritedSeedOfExactType.
  /// Exposed for testing. Do not use in production code.
  Set<Branch> get dependents => _dependents;

  /// The mounted child branch. Exposed for testing.
  /// Do not use in production code.
  Branch? get childBranch => _child;

  // --- Lifecycle ---

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  /// The rebuild hook of an inherited branch: reconcile the single child
  /// against the current seed's child config.
  @override
  void performRebuild() {
    _child = updateChild(_child, _typed.child, 0);
  }

  @override
  void update(Seed newSeed) {
    assert(
      Seed.canUpdate(seed, newSeed),
      'update() called with a Seed that fails canUpdate; '
      'use unmount() + mount() for type/key changes.',
    );
    final old = _typed;
    // Flutter ProxyElement order: notify dependents BEFORE the base update
    // invokes the rebuild hook. A dependent inside the
    // child subtree is then force-rebuilt exactly once during reconciliation
    // (clearing its dirty flag) instead of rebuilding a second time when the
    // owner drains the dirty set.
    notifyDependents(old, newSeed as InheritedSeed<T>);
    super.update(newSeed);
  }

  /// Invalidates the dependents affected by the config change from [oldSeed]
  /// to [newSeed].
  ///
  /// The base rule is InheritedWidget's: when
  /// [InheritedSeed.updateShouldNotify] is true, EVERY dependent is
  /// invalidated. [InheritedModelBranch] overrides this to consult each
  /// dependent's recorded aspects.
  @protected
  void notifyDependents(InheritedSeed<T> oldSeed, InheritedSeed<T> newSeed) {
    if (!newSeed.updateShouldNotify(oldSeed)) return;
    for (final dep in List.of(_dependents)) {
      dep.dependencyChanged();
    }
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    for (final dep in List.of(_dependents)) {
      dep.removeDependency(this);
    }
    _dependents.clear();
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}

/// Provides an ambient value of type [T] whose dependents may subscribe to a
/// single ASPECT of it — the InheritedModel analogue.
///
/// A dependent subscribes with
///   `context.dependOnInheritedSeedOfExactType<T>(aspect: someAspect)`
/// and is invalidated only when [updateShouldNotifyDependent] reports the
/// change as affecting one of the aspects it asked for. A dependent that
/// omits the aspect depends on the whole value, exactly as under
/// [InheritedSeed].
///
/// Lookup is unchanged — the parent walk still matches the nearest provider
/// of exact value-type [T] — so a plain
/// `dependOnInheritedSeedOfExactType<T>()` finds an
/// `InheritedModelSeed<T, A>` too and gets a whole-value dependency.
///
/// The house shape for a consumer is its own static `of`:
///
/// ```dart
/// static Environment? of(TreeContext context, {Lane? aspect}) =>
///     context.dependOnInheritedSeedOfExactType<Environment>(aspect: aspect);
/// ```
class InheritedModelSeed<T extends Object, A extends Object>
    extends InheritedSeed<T> {
  /// Creates an aspect-scoped provider of [value] over [child].
  const InheritedModelSeed({
    required super.value,
    required super.child,
    super.key,
  });

  /// Whether a dependent that subscribed to [dependencies] must rebuild now
  /// that this seed has replaced [oldSeed].
  ///
  /// Called once per aspect-scoped dependent, and only after
  /// [InheritedSeed.updateShouldNotify] already returned true — so the
  /// default (`true`) makes a subclass that ignores aspects behave exactly
  /// like an [InheritedSeed]. [dependencies] is never empty: a dependent that
  /// asked for no aspect depends on the whole value and is invalidated
  /// without consulting this hook.
  bool updateShouldNotifyDependent(
    covariant InheritedModelSeed<T, A> oldSeed,
    Set<A> dependencies,
  ) => true;

  @override
  InheritedModelBranch<T, A> createBranch() => InheritedModelBranch<T, A>(this);
}

/// Mounted branch for [InheritedModelSeed]: [InheritedBranch] plus
/// per-dependent aspect bookkeeping. [notifyDependents] consults
/// [InheritedModelSeed.updateShouldNotifyDependent] with the aspects each
/// dependent asked for and invalidates only those it reports as affected.
///
/// Recorded limitation (it matches the plain provider): a dependency is
/// recorded at lookup and cleared only by [removeDependent] or unmount — the
/// spine never resets dependencies between rebuilds. A branch that asks for
/// different aspects across successive builds therefore ACCUMULATES them and
/// is over-notified, never under-notified. Narrowing would need a per-build
/// dependency reset on `Branch`, which the spine deliberately does not have.
class InheritedModelBranch<T extends Object, A extends Object>
    extends InheritedBranch<T> {
  /// Creates the branch for [seed].
  InheritedModelBranch(InheritedModelSeed<T, A> super.seed);

  // Per-dependent aspect subscriptions. An EMPTY set means "the whole value"
  // (the dependent asked without an aspect); it is sticky, so a later
  // aspect-scoped lookup by the same branch cannot narrow a whole-value
  // dependency.
  final Map<Branch, Set<A>> _aspects = {};

  /// The aspects [branch] subscribed to, or null when it is not a dependent;
  /// an empty set means a whole-value dependency. Exposed for testing.
  /// Do not use in production code.
  Set<A>? aspectsOf(Branch branch) => _aspects[branch];

  @override
  void addDependent(Branch branch, {Object? aspect}) {
    if (aspect != null && aspect is! A) {
      throw ArgumentError.value(
        aspect,
        'aspect',
        'InheritedModelSeed<$T, $A> scopes dependencies by $A; got a '
            '${aspect.runtimeType}. Pass an aspect of type $A, or none to depend '
            'on the whole value.',
      );
    }
    super.addDependent(branch);
    final existing = _aspects[branch];
    if (existing != null && existing.isEmpty) return; // whole-value is sticky
    if (aspect == null) {
      _aspects[branch] = <A>{};
      return;
    }
    (_aspects[branch] ??= <A>{}).add(aspect as A);
  }

  @override
  void removeDependent(Branch branch) {
    _aspects.remove(branch);
    super.removeDependent(branch);
  }

  @override
  void notifyDependents(InheritedSeed<T> oldSeed, InheritedSeed<T> newSeed) {
    final newModel = newSeed as InheritedModelSeed<T, A>;
    final oldModel = oldSeed as InheritedModelSeed<T, A>;
    if (!newModel.updateShouldNotify(oldModel)) return;
    for (final dep in List.of(_dependents)) {
      final aspects = _aspects[dep];
      if (aspects == null ||
          aspects.isEmpty ||
          newModel.updateShouldNotifyDependent(oldModel, aspects)) {
        dep.dependencyChanged();
      }
    }
  }

  @override
  void unmount() {
    super.unmount();
    _aspects.clear();
  }
}
