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

  // null when idle; non-null during a flush pass (debug-only — always null
  // in release).
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
  void scheduleRebuildFor(Branch branch) {
    assert(
      _builtThisPass == null || !_builtThisPass!.contains(branch),
      'branch ${branch.branchId} re-dirtied after it was already built in '
      'this flush pass; performRebuild must not re-dirty an already-built '
      'branch',
    );
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
  /// Branches dirtied mid-flush are rebuilt in the same pass and included.
  List<Branch> flush() {
    final rebuilt = <Branch>[];
    assert(() {
      _builtThisPass = {};
      return true;
    }());
    try {
      while (_dirtyBranches.isNotEmpty) {
        final branch = _dirtyBranches.first;
        _dirtyBranches.remove(branch);
        final willRebuild = branch.mounted && branch.dirty;
        branch.rebuild();
        if (willRebuild) rebuilt.add(branch);
        assert(() {
          _builtThisPass!.add(branch);
          return true;
        }());
      }
    } finally {
      assert(() {
        _builtThisPass = null;
        return true;
      }());
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
