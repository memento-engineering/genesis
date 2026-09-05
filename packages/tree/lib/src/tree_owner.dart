import 'dart:collection';

import 'branch.dart';
import 'seed.dart';

/// Signature for argument-free callbacks.
typedef VoidCallback = void Function();

/// Owns the root branch, holds the dirty set, and drives synchronous
/// depth-ordered flushes — the BuildOwner.buildScope analogue.
class TreeOwner {
  final SplayTreeSet<Branch> _dirtyBranches = SplayTreeSet((a, b) {
    final d = a.depth.compareTo(b.depth);
    return d != 0 ? d : a.branchId.compareTo(b.branchId);
  });

  /// Called on the empty→non-empty edge of the dirty set: fires exactly once
  /// when work first becomes available, and again only after a [flush]
  /// drains the set.
  VoidCallback? onNeedsFlush;

  Branch? _root;
  int _nextId = 0;

  // Non-null only during a flush pass: every branch this pass has begun
  // building. Enforced in release, not just debug — the drain loop is
  // unbounded by design, and one build per branch per pass is what bounds it.
  Set<Branch>? _builtThisPass;

  /// Issues the next owner-scoped branch id: a monotonic decimal string
  /// starting at '0'. Stable for the branch's lifetime.
  String issueId() => (_nextId++).toString();

  /// Mounts [seed] as the root branch of this owner's tree.
  Branch mountRoot(Seed seed) {
    assert(
      _root == null,
      'mountRoot called with an existing root; call unmountRoot() first',
    );
    final branch = seed.createBranch();
    branch.owner = this;
    branch.mount(null, null);
    _root = branch;
    return branch;
  }

  /// Adds [branch] to the dirty set; called by [Branch.markNeedsRebuild].
  ///
  /// Throws [StateError] when [branch] has already been built in the flush
  /// pass now running: rebuilding it again would drain forever. The common
  /// cause is a state change made from inside `build()` (setState during
  /// build) — move it to an event handler or a passive effect.
  void scheduleRebuildFor(Branch branch) {
    final builtThisPass = _builtThisPass;
    if (builtThisPass != null && builtThisPass.contains(branch)) {
      throw StateError(
        'branch ${branch.branchId} was re-dirtied after it had already been '
        'built in this flush pass. A branch that rebuilt itself during its '
        'own build (setState during build), or that a later build re-dirties, '
        'would loop the drain forever. Move the state change to an event '
        'handler or a passive effect.',
      );
    }
    final wasEmpty = _dirtyBranches.isEmpty;
    _dirtyBranches.add(branch);
    if (wasEmpty) onNeedsFlush?.call();
  }

  /// Drains the dirty set in depth order (parents before children),
  /// rebuilding each branch, and returns the branches this call actually
  /// rebuilt, in flush order — the drained dirty set exposed to render
  /// backends.
  ///
  /// A drained branch is included iff it was still mounted and dirty when
  /// drained. A branch that was force-rebuilt earlier by an update cascade
  /// (the update cascade clears its dirty flag) or unmounted after being
  /// scheduled is drained but excluded — it was not rebuilt by this call.
  /// Branches dirtied mid-flush are rebuilt in the same pass and included —
  /// but a branch already built in this pass may not be re-dirtied; that
  /// throws [StateError] (see [scheduleRebuildFor]).
  List<Branch> flush() {
    final rebuilt = <Branch>[];
    final builtThisPass = _builtThisPass = <Branch>{};
    try {
      while (_dirtyBranches.isNotEmpty) {
        final branch = _dirtyBranches.first;
        _dirtyBranches.remove(branch);
        // Recorded BEFORE the rebuild: a branch that re-dirties itself during
        // its own build must trip the guard at the call site, not queue a
        // second build of the same branch.
        builtThisPass.add(branch);
        final willRebuild = branch.mounted && branch.dirty;
        branch.rebuild();
        if (willRebuild) rebuilt.add(branch);
      }
    } finally {
      _builtThisPass = null;
    }
    return rebuilt;
  }

  /// Unmounts the current root branch, if any.
  void unmountRoot() {
    if (_root?.mounted == true) _root!.unmount();
    _root = null;
  }

  /// Unmounts the root and clears the dirty set.
  void dispose() {
    unmountRoot();
    _dirtyBranches.clear();
  }
}
