/// The lifecycle phase in which a tree driver is currently executing.
enum TreeLifecyclePhase {
  /// No explicit lifecycle callback or owner flush is active.
  notInTreePhase,

  /// A state object is running its one-time initialization callback.
  initState,

  /// A state object is responding to inherited dependency changes.
  didChangeDependencies,

  /// A element is rebuilding its tree contribution.
  building,

  /// A state object is running its teardown callback.
  dispose,
}

/// Tracks tree lifecycle scopes and enforces inherited-dependency timing.
///
/// Explicit scopes take precedence over [isBuilding]. Scopes nest and always
/// restore the prior explicit phase, including when their callback throws.
final class TreeLifecyclePhaseGuard {
  /// Creates a guard, optionally composing an existing build-phase signal.
  TreeLifecyclePhaseGuard({bool Function()? isBuilding})
    : _isBuilding = isBuilding;

  final bool Function()? _isBuilding;
  TreeLifecyclePhase? _explicitPhase;

  /// The active explicit phase, owner build phase, or
  /// [TreeLifecyclePhase.notInTreePhase].
  TreeLifecyclePhase get phase {
    final explicitPhase = _explicitPhase;
    if (explicitPhase != null) return explicitPhase;
    if (_isBuilding?.call() ?? false) return TreeLifecyclePhase.building;
    return TreeLifecyclePhase.notInTreePhase;
  }

  /// Runs [body] in [phase], restoring the previous explicit phase afterward.
  R runInPhase<R>(TreeLifecyclePhase phase, R Function() body) {
    final previousPhase = _explicitPhase;
    _explicitPhase = phase;
    try {
      return body();
    } finally {
      _explicitPhase = previousPhase;
    }
  }

  /// Verifies that an inherited dependency of type [T] may be registered.
  ///
  /// Dependency registration is legal during
  /// [TreeLifecyclePhase.didChangeDependencies] and
  /// [TreeLifecyclePhase.building]. The historical initialization and
  /// teardown diagnostics remain debug assertions; registration outside all
  /// tree phases throws [StateError] in every build mode.
  void checkCanDependOnInheritedValueOfExactType<T extends Object>() {
    switch (phase) {
      case TreeLifecyclePhase.didChangeDependencies:
      case TreeLifecyclePhase.building:
        return;
      case TreeLifecyclePhase.initState:
        assert(
          false,
          'dependOnInheritedValueOfExactType<$T>() called from initState. '
          'initState never re-runs, so caching the value read here goes stale '
          'when the provider changes. For a one-shot read use '
          'getInheritedValueOfExactType<$T>(); to cache and track the value, '
          'move '
          'the lookup to didChangeDependencies(), which re-runs on every change.',
        );
        return;
      case TreeLifecyclePhase.dispose:
        assert(
          false,
          'dependOnInheritedValueOfExactType<$T>() called from dispose. The '
          'element is unmounting — a dependency registered now can never observe '
          'a change. Use getInheritedValueOfExactType<$T>() for a last read '
          'during teardown.',
        );
        return;
      case TreeLifecyclePhase.notInTreePhase:
        throw StateError(
          'dependOnInheritedValueOfExactType<$T>() called outside a tree '
          'lifecycle phase (TreeLifecyclePhase.notInTreePhase). Register '
          'inherited dependencies from didChangeDependencies() or build().',
        );
    }
  }

  /// Legacy spelling for [checkCanDependOnInheritedValueOfExactType].
  @Deprecated('Use checkCanDependOnInheritedValueOfExactType instead.')
  void checkCanDependOnInheritedSeedOfExactType<T extends Object>() =>
      checkCanDependOnInheritedValueOfExactType<T>();
}
