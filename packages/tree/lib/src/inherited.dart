/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'branch.dart';
import 'seed.dart';

/// Provides an ambient value of type [T] to all descendants in the tree —
/// the InheritedWidget analogue.
///
/// Usage:
///   `InheritedSeed<String>(value: 'hello', child: MySeed())`
///
/// Descendants call:
///   `context.dependOnInheritedSeedOfExactType<String>()`
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
  void addDependent(Branch branch) {
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
    if ((newSeed as InheritedSeed<T>).updateShouldNotify(old)) {
      for (final dep in List.of(_dependents)) {
        dep.dependencyChanged();
      }
    }
    super.update(newSeed);
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
