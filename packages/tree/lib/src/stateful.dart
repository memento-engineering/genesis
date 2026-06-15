/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'component_branch.dart';
import 'seed.dart';
import 'tree_context.dart';
import 'tree_owner.dart';

/// A [Seed] whose branch owns mutable [State] — the StatefulWidget analogue.
abstract class StatefulSeed extends Seed {
  /// Creates a stateful seed, optionally [key]ed.
  const StatefulSeed({super.key});

  /// Creates the mutable state for a branch of this seed.
  @factory
  State<StatefulSeed> createState();

  @override
  StatefulBranch createBranch() => StatefulBranch(this);
}

/// Mutable state owned by a [StatefulBranch], with the
/// initState/didChangeDependencies/build/dispose lifecycle.
abstract class State<T extends StatefulSeed> {
  /// The current [StatefulSeed] configuration of the owning branch.
  T get seed => _branch!.seed as T;

  /// The owning branch's capability handle: a separate object, never
  /// the branch itself; throws [StateError] when used after unmount.
  TreeContext get context {
    assert(_branch != null, 'context accessed outside branch lifecycle');
    return _branch!.context;
  }

  StatefulBranch? _branch;

  /// Called exactly once, before the first build.
  @protected
  void initState() {}

  /// Called after [initState] and whenever a depended-on inherited value
  /// changes, before the next build.
  @protected
  void didChangeDependencies() {}

  /// Describes the child subtree for the current configuration and state.
  Seed build(TreeContext context);

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

/// Mounted branch for a [StatefulSeed]: creates and owns the [State], drives
/// its lifecycle, and delegates [build] to it.
class StatefulBranch extends ComponentBranch {
  /// Creates the branch and its [State] for [seed].
  StatefulBranch(StatefulSeed seed) : super(seed) {
    _state = seed.createState();
    _state._branch = this;
  }

  late final State<StatefulSeed> _state;
  bool _firstBuild = true;
  bool _needsDidChangeDependencies = false;

  /// The mutable state owned by this branch.
  ///
  /// `@protected`: only this branch and its subclasses reach it (a domain
  /// element upgrades the return type; an actionable element forwards to it).
  /// It is **not** public API — external layers must not reach into a branch's
  /// `State`. Tests that need it access it with an
  /// `invalid_use_of_protected_member` ignore.
  @protected
  State<StatefulSeed> get state => _state;

  @override
  Seed build(TreeContext context) => _state.build(context);

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
