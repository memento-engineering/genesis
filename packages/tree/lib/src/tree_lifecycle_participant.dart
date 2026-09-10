/// A call-scoped capability for reading inherited values without subscribing.
///
/// The reader is valid only for the `initState` call that receives it. Retain
/// neither the reader nor values that should stay synchronized with the tree;
/// watched values belong in
/// [TreeLifecycleParticipant.didChangeDependencies].
abstract interface class TreeSnapshotReader {
  /// Reads the nearest inherited value of exact type [T] without subscribing.
  T? read<T extends Object>();
}

/// A call-scoped capability for reading and subscribing to inherited values.
///
/// The reader is valid only for the `didChangeDependencies` call that receives
/// it. Cache the returned value in the participant; the lifecycle driver calls
/// [TreeLifecycleParticipant.didChangeDependencies] again whenever a watched
/// inherited value changes.
abstract interface class TreeWatchingReader {
  /// Watches the nearest inherited value of exact type [T].
  T? watch<T extends Object>();
}

/// Whether one dependency callback is still the participant's current pass.
///
/// A scope starts current and is safe to retain across an async gap. The next
/// dependency pass or lifecycle teardown changes [isCurrent] monotonically to
/// false. A scope only reports supersession: it neither cancels nor schedules
/// work, and it does not replace a separate mountedness probe when a caller
/// also needs to know whether its tree branch remains mounted.
abstract interface class TreeDependencyScope {
  /// Whether the dependency pass that supplied this scope is still current.
  bool get isCurrent;
}

/// Lifecycle hooks for a long-lived object that is not a tree node.
///
/// A lifecycle driver passes a narrowly scoped reader to each dependency
/// callback and a retainable per-pass scope instead of exposing a persistent
/// tree capability. The participant may cache returned values and retain the
/// scope that qualifies them, but each reader expires when its callback
/// returns.
mixin TreeLifecycleParticipant {
  /// Runs once when the participant enters the tree.
  ///
  /// Use [reader] only for one-shot snapshots. Values that must stay current
  /// belong in [didChangeDependencies].
  void initState(TreeSnapshotReader reader) {}

  /// Runs after [initState] and whenever a watched inherited value changes.
  ///
  /// Use [reader] to replace cached dependency values before the subtree
  /// rebuilds. Retain [scope] only with values or async work produced by this
  /// pass so they can observe when a later pass supersedes them.
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) {}

  /// Runs when an owning lifecycle driver leaves the tree.
  void dispose() {}
}
