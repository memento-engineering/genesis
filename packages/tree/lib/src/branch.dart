import 'package:meta/meta.dart';

import 'seed.dart';
import 'tree_context.dart';
import 'tree_owner.dart';

/// Mounted, persistent node in the tree — the Element analogue (ADR-0001
/// Decision 2).
///
/// `Branch` core is artifact-agnostic (ADR-0001 Decision 3): it owns identity,
/// lifecycle (mount/update/unmount), keyed reconciliation, dirtiness, and the
/// single [performRebuild] hook. It carries no build contract — the
/// composition layer (`ComponentBranch` and friends) defines the hook as
/// re-running `build()`; other branches define their own artifact response.
///
/// Per ADR-0001 Decision 2 (A8), `Branch` deliberately does NOT implement
/// [TreeContext]. The build-time capability handle is a separate object
/// obtained via [context]; it throws [StateError] on use after this branch
/// unmounts, so a handle held across an async gap fails loudly instead of
/// silently acting on a stale node.
abstract class Branch {
  /// Creates a branch configured by [seed].
  Branch(Seed seed) : _seed = seed;

  Seed _seed;

  /// The current [Seed] configuration for this branch.
  Seed get seed => _seed;

  /// Stable id for this mounted branch; assigned at mount time via
  /// [TreeOwner.issueId] and never changes during the branch's lifetime.
  late final String branchId;

  /// The key of the underlying [Seed] config, or null if unkeyed.
  Object? get key => _seed.key;

  TreeContext? _context;

  /// The capability handle for this branch (ADR-0001 Decision 2 / A8).
  ///
  /// This is the object the composition layer passes to `build()` and
  /// surfaces as `State.context`. It is never the branch itself; after this
  /// branch unmounts the handle throws [StateError] on use — except
  /// [TreeContext.mounted], which stays queryable as the staleness probe.
  TreeContext get context => _context ??= createTreeContext(this);

  // Providers (InheritedBranchBase ancestors) this branch currently
  // depends on.
  final Set<InheritedBranchBase> _dependencies = {};

  /// Returns the nearest ancestor value provided via `InheritedSeed<T>` of
  /// exact type [T], registering this branch as a dependent; null when no
  /// such ancestor exists.
  T? dependOnInheritedSeedOfExactType<T extends Object>() {
    Branch? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is InheritedBranchBase) {
        final value = ancestor.getValueAs<T>();
        if (value != null) {
          ancestor.addDependent(this);
          _dependencies.add(ancestor);
          return value;
        }
      }
      ancestor = ancestor._parent;
    }
    return null;
  }

  /// Marks this branch dirty so the next [TreeOwner.flush] rebuilds it.
  void markNeedsRebuild() {
    if (mounted && !_dirty) {
      _dirty = true;
      owner?.scheduleRebuildFor(this);
    }
  }

  /// Called by `InheritedBranch` when a depended-on value changes.
  /// Default: delegates to [markNeedsRebuild].
  /// `StatefulBranch` overrides this to also flag didChangeDependencies.
  void dependencyChanged() => markNeedsRebuild();

  /// Runs [performRebuild] when this branch is mounted and dirty (or when
  /// [force] is true — the ADR-0001 Decision 4 update path). Clears the dirty
  /// flag first, so a branch force-rebuilt during reconciliation is skipped
  /// when the owner later drains it in the same flush.
  void rebuild({bool force = false}) {
    if (mounted && (_dirty || force)) {
      _dirty = false;
      performRebuild();
    }
  }

  /// The single rebuild hook (ADR-0001 Decision 3). `Branch` core attaches no
  /// meaning to it; the composition layer defines it as re-running `build()`,
  /// and non-component branches define their own artifact response.
  @protected
  void performRebuild() {}

  // --- Internal state ---

  Branch? _parent;
  bool _mounted = false;
  bool _dirty = false;

  /// The [TreeOwner] this branch is mounted under. Set by
  /// [TreeOwner.mountRoot] for roots and inherited from the parent in
  /// [mount].
  TreeOwner? owner;

  /// Depth from the root (root = 0). Drives the owner's depth-ordered flush.
  int depth = 0;

  /// Whether this branch is currently mounted in a tree.
  bool get mounted => _mounted;

  /// Whether this branch is currently marked as needing rebuild.
  bool get dirty => _dirty;

  /// Providers this branch depends on. Exposed for testing.
  /// Do not use in production code.
  Set<Branch> get dependencies => _dependencies;

  // --- Traversal ---

  /// Calls [visitor] once for each direct child of this branch, in tree
  /// order (ADR-0001 Decision 5).
  ///
  /// `Branch` core holds no children, so the base implementation visits
  /// nothing; subclasses that own children override this. The walk is
  /// shallow — callers recurse to traverse a subtree. The tree must not be
  /// mutated during a visit.
  void visitChildren(void Function(Branch child) visitor) {}

  // --- Lifecycle ---

  /// Attaches this branch into the tree under [parent] at [slot].
  @mustCallSuper
  void mount(Branch? parent, Object? slot) {
    assert(
      !_mounted,
      'mount() called on already-mounted branch (id=$branchId).',
    );
    _parent = parent;
    owner ??= parent?.owner;
    assert(
      owner != null,
      'mount() requires a non-null owner; call TreeOwner.mountRoot() '
      'for root branches, or mount under a parent that has an owner.',
    );
    branchId = owner!.issueId();
    _mounted = true;
    depth = (parent?.depth ?? -1) + 1;
  }

  /// Updates the config node when [Seed.canUpdate] is true, then invokes the
  /// rebuild path (ADR-0001 Decision 4 / A9): a config update reaches
  /// [performRebuild] with the new [seed] already in place. What the hook
  /// does is layered per Decision 3 — components re-run `build()`;
  /// non-component branches respond with their own artifact semantics.
  @mustCallSuper
  void update(Seed newSeed) {
    assert(_mounted, 'update() called on unmounted branch.');
    assert(
      Seed.canUpdate(_seed, newSeed),
      'update() called with a Seed that fails canUpdate; '
      'use unmount() + mount() for type/key changes.',
    );
    _seed = newSeed;
    rebuild(force: true);
  }

  /// Detaches this branch from the tree.
  @mustCallSuper
  void unmount() {
    assert(_mounted, 'unmount() called on already-unmounted branch.');
    for (final dep in List.of(_dependencies)) {
      dep.removeDependent(this);
    }
    _mounted = false;
    _parent = null;
  }

  /// Package-internal: called only by `InheritedBranch.removeDependent`.
  void removeDependency(Branch dep) {
    _dependencies.remove(dep);
  }

  // --- Single-child reconciliation ---

  /// Reconciles [child] against [newSeed] at [slot].
  Branch? updateChild(Branch? child, Seed? newSeed, Object? slot) {
    if (newSeed == null) {
      child?.unmount();
      return null;
    }
    if (child != null) {
      if (Seed.canUpdate(child._seed, newSeed)) {
        child.update(newSeed);
        return child;
      }
      child.unmount();
    }
    final branch = newSeed.createBranch();
    branch.mount(this, slot);
    return branch;
  }

  // --- Multi-child keyed reconciliation ---

  /// Reconciles [oldChildren] against [newSeeds] by key identity.
  List<Branch> updateChildren(List<Branch> oldChildren, List<Seed> newSeeds) {
    final Map<Object, Branch> keyedOld = {};
    final List<Branch> unkeyedOld = [];
    for (final branch in oldChildren) {
      if (branch._seed.key != null) {
        keyedOld[branch._seed.key!] = branch;
      } else {
        unkeyedOld.add(branch);
      }
    }

    int unkeyedCursor = 0;
    final result = <Branch>[];

    for (int i = 0; i < newSeeds.length; i++) {
      final newSeed = newSeeds[i];
      Branch? match;
      if (newSeed.key != null) {
        match = keyedOld.remove(newSeed.key);
      } else if (unkeyedCursor < unkeyedOld.length) {
        match = unkeyedOld[unkeyedCursor++];
      }

      if (match != null && Seed.canUpdate(match._seed, newSeed)) {
        match.update(newSeed);
        result.add(match);
      } else {
        match?.unmount();
        final branch = newSeed.createBranch();
        branch.mount(this, i);
        result.add(branch);
      }
    }

    for (final branch in keyedOld.values) {
      branch.unmount();
    }
    for (int i = unkeyedCursor; i < unkeyedOld.length; i++) {
      unkeyedOld[i].unmount();
    }

    return result;
  }
}

/// Package-internal bridge. Defined alongside [Branch] so that
/// [Branch._dependencies] can be typed `Set<InheritedBranchBase>` without
/// importing `inherited.dart` (which would create a problematic cross-library
/// private-access cycle). Do not use or extend directly — use
/// `InheritedSeed`/`InheritedBranch` instead.
@internal
abstract class InheritedBranchBase extends Branch {
  /// Forwards [seed] to [Branch].
  InheritedBranchBase(super.seed);

  /// Returns this branch's wrapped value as [T] if its exact value-type
  /// equals [T]; null otherwise. Used by the parent-walk in
  /// [Branch.dependOnInheritedSeedOfExactType].
  T? getValueAs<T extends Object>();

  /// Registers [branch] as a dependent. Idempotent (set-add).
  void addDependent(Branch branch);

  /// Removes [branch] from this branch's dependent set and clears the
  /// corresponding back-link in [branch]'s dependency set.
  void removeDependent(Branch branch);
}
