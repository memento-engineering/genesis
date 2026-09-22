import 'dart:collection';

import 'package:meta/meta.dart';

import 'component.dart';
import 'element.dart';
import 'tree_lifecycle_phase.dart';

/// Signature for argument-free callbacks.
typedef VoidCallback = void Function();

/// Owns the root element, holds the dirty set, and drives synchronous
/// depth-ordered flushes — the BuildOwner.buildScope analogue.
class BuildOwner {
  /// Creates a build owner and composes its existing flush marker into the
  /// shared lifecycle phase guard.
  BuildOwner() {
    lifecyclePhaseGuard = TreeLifecyclePhaseGuard(
      isBuilding: () => _builtThisPass != null,
    );
  }

  final SplayTreeSet<Element> _dirtyElements = SplayTreeSet((a, b) {
    final d = a.depth.compareTo(b.depth);
    return d != 0 ? d : a.elementId.compareTo(b.elementId);
  });

  /// Called on the empty→non-empty edge of the dirty set: fires exactly once
  /// when work first becomes available, and again only after a [flush]
  /// drains the set.
  VoidCallback? onNeedsFlush;

  Element? _root;
  int _nextId = 0;

  // Non-null only during a flush pass: every element this pass has begun
  // building. Enforced in release, not just debug — the drain loop is
  // unbounded by design, and one build per element per pass is what bounds it.
  Set<Element>? _builtThisPass;

  // Set only while assertions are enabled. Unlike [_builtThisPass], this
  // follows nested rebuilds so a synchronous update cascade is checked against
  // the element whose hook is actually executing.
  Element? _debugCurrentBuildTarget;

  /// The shared lifecycle phase definition for drivers owned by this tree.
  late final TreeLifecyclePhaseGuard lifecyclePhaseGuard;

  /// Issues the next owner-scoped element id: a monotonic decimal string
  /// starting at '0'. Stable for the element's lifetime.
  String issueId() => (_nextId++).toString();

  /// Package-internal: runs [build] with [element] installed as the current
  /// debug build target, restoring the enclosing target even when it throws.
  ///
  /// [build] executes exactly once in every build mode. Target bookkeeping is
  /// assertion-only, so release builds pay no scope-management cost.
  @internal
  void runElementBuild(Element element, VoidCallback build) {
    Element? previousTarget;
    assert(() {
      previousTarget = _debugCurrentBuildTarget;
      _debugCurrentBuildTarget = element;
      return true;
    }());
    try {
      build();
    } finally {
      assert(() {
        _debugCurrentBuildTarget = previousTarget;
        return true;
      }());
    }
  }

  /// Legacy spelling for [runElementBuild].
  @Deprecated('Use runElementBuild instead.')
  void runBranchBuild(Element element, VoidCallback build) =>
      runElementBuild(element, build);

  /// Mounts [component] as the root element of this owner's tree.
  Element mountRoot(Component component) {
    assert(
      _root == null,
      'mountRoot called with an existing root; call unmountRoot() first',
    );
    final element = component.createElement();
    element.owner = this;
    element.mount(null, null);
    _root = element;
    return element;
  }

  /// Adds [element] to the dirty set; called by [Element.markNeedsRebuild].
  ///
  /// Throws [StateError] when [element] has already been built in the flush
  /// pass now running: rebuilding it again would drain forever. The common
  /// cause is a state change made from inside `build()` (setState during
  /// build) — move it to an event handler or a passive effect.
  void scheduleRebuildFor(Element element) {
    final builtThisPass = _builtThisPass;
    if (builtThisPass != null && builtThisPass.contains(element)) {
      throw StateError(
        'element ${element.elementId} was re-dirtied after it had already '
        'been built in this flush pass. An element that rebuilt itself '
        'during its '
        'own build (setState during build), or that a later build re-dirties, '
        'would loop the drain forever. Move the state change to an event '
        'handler or a passive effect.',
      );
    }
    assert(
      _debugCurrentBuildTarget == null ||
          _debugIsDescendantOf(element, _debugCurrentBuildTarget!),
      'element ${element.elementId} (${element.runtimeType}) was marked dirty '
      'while element ${_debugCurrentBuildTarget?.elementId} '
      '(${_debugCurrentBuildTarget.runtimeType}) was building. An element '
      'dirtied during build must be a descendant of the element currently '
      'building. Parents build before children, so a dirty descendant is '
      'always built; any other element may not be visited in this flush pass.',
    );
    final wasEmpty = _dirtyElements.isEmpty;
    _dirtyElements.add(element);
    if (wasEmpty) onNeedsFlush?.call();
  }

  bool _debugIsDescendantOf(Element candidate, Element target) {
    while (candidate.depth > target.depth) {
      final parent = debugParentOf(candidate);
      if (parent == null) return false;
      candidate = parent;
    }
    return identical(candidate, target);
  }

  /// Drains the dirty set in depth order (parents before children),
  /// rebuilding each element, and returns the elements this call actually
  /// rebuilt, in flush order — the drained dirty set exposed to render
  /// backends.
  ///
  /// A drained element is included iff it was still mounted and dirty when
  /// drained. A element that was force-rebuilt earlier by an update cascade
  /// (the update cascade clears its dirty flag) or unmounted after being
  /// scheduled is drained but excluded — it was not rebuilt by this call.
  /// Branches dirtied mid-flush are rebuilt in the same pass and included —
  /// but a element already built in this pass may not be re-dirtied; that
  /// throws [StateError] (see [scheduleRebuildFor]).
  List<Element> flush() {
    final rebuilt = <Element>[];
    final builtThisPass = _builtThisPass = <Element>{};
    try {
      while (_dirtyElements.isNotEmpty) {
        final element = _dirtyElements.first;
        _dirtyElements.remove(element);
        // Recorded BEFORE the rebuild: a element that re-dirties itself during
        // its own build must trip the guard at the call site, not queue a
        // second build of the same element.
        builtThisPass.add(element);
        final willRebuild = element.mounted && element.dirty;
        element.rebuild();
        if (willRebuild) rebuilt.add(element);
      }
    } finally {
      _builtThisPass = null;
    }
    return rebuilt;
  }

  /// Unmounts the current root element, if any.
  void unmountRoot() {
    if (_root?.mounted == true) _root!.unmount();
    _root = null;
  }

  /// Unmounts the root and clears the dirty set.
  void dispose() {
    unmountRoot();
    _dirtyElements.clear();
  }
}

/// Legacy name for [BuildOwner].
@Deprecated('Use BuildOwner instead.')
typedef TreeOwner = BuildOwner;
