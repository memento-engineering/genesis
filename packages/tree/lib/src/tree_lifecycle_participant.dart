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

/// Lifecycle hooks for a long-lived object that is not a tree node.
///
/// A lifecycle driver passes a narrowly scoped reader to each dependency
/// callback instead of exposing a persistent tree capability. The participant
/// may cache returned values, but each reader expires when its callback
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
  /// rebuilds.
  void didChangeDependencies(TreeWatchingReader reader) {}

  /// Runs when an owning lifecycle driver leaves the tree.
  void dispose() {}
}
