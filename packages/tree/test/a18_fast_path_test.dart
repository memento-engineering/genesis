// A18 (ratified PORT, bead genesis-4m1): the identical-config fast path.
//
// In reconciliation (Branch.updateChild, and the multichild path that now
// delegates to it), an existing child reconciled against an *identical* seed
// is returned untouched — no update(), no rebuild, no subtree cascade. The
// skip is identity-only (`identical()`, never `Seed.operator==`) and lives in
// reconciliation only: Branch.update keeps its A9 force semantics.
//
// These are the 10 gating tests from docs/design/a9-fast-path-analysis.md §6.
// They pin: the skip itself (#1), const pruning (#2), identity-not-value (#3),
// provider invalidation surviving the skip (#4), the A14 flush inclusion delta
// (#5), out-of-flush timing (#6), multichild coverage (#7), update() unchanged
// (#8), the wire-realism guard (#9), and a harvest-shape conformance check
// over a skipped subtree (#10).
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

// --- Fixtures ----------------------------------------------------------------

class _Tracker {
  int builds = 0;
}

/// A stateless seed that counts its build()s and returns a const child leaf.
class _CountingSeed extends StatelessSeed {
  const _CountingSeed(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    return const Leaf('counting-child');
  }
}

/// A parent whose build() returns the SAME child instance every time — either
/// a `const` (Dart-canonicalized → identical) child, or a caller-cached one.
/// Across a parent rebuild the returned child is identical, so the fast path
/// prunes the entire child subtree. The child's own builder counts via
/// [childTracker], so a re-run would be observable.
class _CachedParentSeed extends StatelessSeed {
  const _CachedParentSeed(this.parentTracker, this.cachedChild);
  final _Tracker parentTracker;
  final Seed cachedChild;
  @override
  Seed build(TreeContext context) {
    parentTracker.builds++;
    // Identical instance on every build → fast path skips its whole subtree.
    return cachedChild;
  }
}

/// A counting child seed whose own build returns a const grandchild Leaf.
class _CountingChildSeed extends StatelessSeed {
  const _CountingChildSeed(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    return const Leaf('grandchild');
  }
}

/// A stateless seed overriding ==/hashCode to VALUE equality. Two distinct
/// instances with the same `id` are `==` but not `identical` — the fast path
/// must NOT skip on these (it consults identical(), never ==).
class _ValueEqSeed extends StatelessSeed {
  const _ValueEqSeed(this.id, this.tracker);
  final String id;
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    return const Leaf('value-eq-child');
  }

  @override
  bool operator ==(Object other) =>
      other is _ValueEqSeed && other.id == id && other.tracker == tracker;

  @override
  int get hashCode => Object.hash(id, tracker);
}

/// A stateless seed that reads a provided String and records each build.
class _DependentSeed extends StatelessSeed {
  _DependentSeed(this.tracker, {super.key});
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    context.dependOnInheritedSeedOfExactType<String>();
    return const Leaf('dependent-child');
  }
}

/// A stateful seed recording the order of didChangeDependencies / build and a
/// build count — used to prove dCD fires before build under the skip.
class _OrderSeed extends StatefulSeed {
  const _OrderSeed(this.log);
  final List<String> log;
  @override
  State<StatefulSeed> createState() => _OrderState();
}

class _OrderState extends State<_OrderSeed> {
  int builds = 0;
  @override
  void didChangeDependencies() => seed.log.add('didChangeDependencies');
  @override
  Seed build(TreeContext context) {
    builds++;
    seed.log.add('build');
    context.dependOnInheritedSeedOfExactType<String>();
    return const Leaf('order-child');
  }
}

/// A non-dependent stateless seed: never reads the provider. Used to prove a
/// non-dependent sibling inside a skipped subtree never rebuilds.
class _NonDependentSeed extends StatelessSeed {
  _NonDependentSeed(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(TreeContext context) {
    tracker.builds++;
    return const Leaf('non-dependent-child');
  }
}

/// Walks a mounted subtree depth-first and renders a stable structural
/// snapshot (the shape a perception harvest would observe): seed tag + ordered
/// children. Two trees with the same shape produce byte-identical strings.
String _harvest(Branch branch) {
  final buffer = StringBuffer();
  void walk(Branch b) {
    final seed = b.seed;
    final tag = seed is Leaf
        ? 'Leaf(${seed.tag})'
        : '${seed.runtimeType}'
              '${seed.key != null ? '#${seed.key}' : ''}';
    buffer.write('<$tag>');
    b.visitChildren(walk);
    buffer.write('</>');
  }

  walk(branch);
  return buffer.toString();
}

void main() {
  // #1 --------------------------------------------------------------------
  group('#1 skip-on-identical', () {
    test('updateChild with an identical seed returns the same branch and does '
        'NOT re-run the child build (build counter stays put)', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(_CountingSeed(tracker)) as StatelessBranch;
      final child = parent.child!;
      expect(tracker.builds, 1, reason: 'one build on mount');

      // Reconcile the parent's child against the SAME instance it already
      // holds: identical → skip.
      final result = parent.updateChild(child, child.seed, 0);

      expect(result, same(child), reason: 'same branch returned as-is');
      expect(
        tracker.builds,
        1,
        reason: 'the fast path skipped update()/rebuild — no rebuild ran',
      );
    });

    test('a bare hook branch is not rebuilt when reconciled with its own '
        'identical seed (performRebuild does not run)', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const Node('root')) as NodeBranch;
      final hook = _HookBranch(const _HookSeed())..mount(root, 0);
      expect(hook.hookRuns, 0);

      final result = root.updateChild(hook, hook.seed, 0);

      expect(result, same(hook));
      expect(
        hook.hookRuns,
        0,
        reason: 'identical skip → performRebuild never ran',
      );
    });
  });

  // #2 --------------------------------------------------------------------
  group('#2 const pruning', () {
    test('a parent whose build() returns a const child — parent update() '
        're-runs the parent builder once; child + grandchild builders do NOT '
        're-run; branch identity preserved', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final parentTracker = _Tracker();
      final childTracker = _Tracker();
      // A single cached child instance (the const-canonicalized / prebuilt
      // pattern): identical across the parent's two builds → pruned.
      final cachedChild = _CountingChildSeed(childTracker);
      final parent =
          owner.mountRoot(_CachedParentSeed(parentTracker, cachedChild))
              as StatelessBranch;
      expect(parentTracker.builds, 1);
      expect(
        childTracker.builds,
        1,
        reason: 'child + grandchild built once on mount',
      );
      final childBranch = parent.child!;

      // Force the parent to rebuild with a fresh (non-identical) parent seed:
      // its build() re-runs and re-emits the SAME child instance, which the
      // fast path then prunes — child + grandchild builders do not re-run.
      parent.update(_CachedParentSeed(parentTracker, cachedChild));

      expect(parentTracker.builds, 2, reason: 'parent builder re-ran once');
      expect(
        childTracker.builds,
        1,
        reason:
            'identical child across builds → pruned; child + grandchild '
            'builders never re-ran',
      );
      expect(
        parent.child,
        same(childBranch),
        reason: 'child identity preserved',
      );
    });
  });

  // #3 --------------------------------------------------------------------
  group('#3 identity-not-value', () {
    test('a seed with value-equality ==/hashCode STILL rebuilds when a '
        'distinct-but-==-equal seed arrives — the skip uses identical(), not '
        '==', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(const Node('root')) as NodeBranch;

      final a = _ValueEqSeed('same', tracker);
      final child = parent.updateChild(null, a, 0)! as StatelessBranch;
      expect(tracker.builds, 1);

      final b = _ValueEqSeed('same', tracker);
      // Guard the fixture: == says equal, identical says distinct.
      expect(a == b, isTrue, reason: 'fixture: value-equal');
      expect(identical(a, b), isFalse, reason: 'fixture: distinct instances');

      final result = parent.updateChild(child, b, 0);

      expect(result, same(child), reason: 'same type+key → updated in place');
      expect(
        tracker.builds,
        2,
        reason: 'NOT skipped: == is irrelevant; only identical() skips',
      );
    });
  });

  // #4 --------------------------------------------------------------------
  group('#4 provider-invalidation-survives-skip', () {
    test('a provider whose new config reuses the IDENTICAL child instance with '
        'a changed value rebuilds each dependent exactly once; '
        'didChangeDependencies fires before build; non-dependent siblings in '
        'the skipped subtree never rebuild', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final depTracker = _Tracker();
      final nonDepTracker = _Tracker();
      final orderLog = <String>[];

      // The provider's child subtree: a Node holding a dependent, a
      // non-dependent sibling, and a stateful order-recorder. Build it ONCE
      // and reuse the IDENTICAL instance across the provider update.
      final sharedChild = Node(
        'container',
        children: [
          _DependentSeed(depTracker, key: ValueKey('dep')),
          _NonDependentSeed(nonDepTracker),
          _OrderSeed(orderLog),
        ],
      );

      final ip =
          owner.mountRoot(
                InheritedSeed<String>(value: 'v1', child: sharedChild),
              )
              as InheritedBranch<String>;
      // First flush settles the initial subtree build.
      owner.flush();
      expect(depTracker.builds, 1);
      expect(nonDepTracker.builds, 1);
      expect(orderLog, equals(['didChangeDependencies', 'build']));

      orderLog.clear();

      // New provider config: changed value, SAME child instance (identical →
      // the child subtree reconcile is skipped). Dependents are invalidated
      // through dependencyChanged independently of the skip.
      ip.update(InheritedSeed<String>(value: 'v2', child: sharedChild));
      owner.flush();

      expect(depTracker.builds, 2, reason: 'dependent rebuilt exactly once');
      expect(
        nonDepTracker.builds,
        1,
        reason: 'non-dependent sibling in the skipped subtree never rebuilt',
      );
      expect(
        orderLog,
        equals(['didChangeDependencies', 'build']),
        reason: 'didChangeDependencies fires before build, exactly once',
      );
    });
  });

  // #5 --------------------------------------------------------------------
  group('#5 A14 inclusion delta', () {
    test('flush() INCLUDES the drain-rebuilt dependents (and still excludes '
        'cascade force-rebuilds); onNeedsFlush fired on the empty→non-empty '
        'edge', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      var needsFlushCalls = 0;
      owner.onNeedsFlush = () => needsFlushCalls++;

      final depTracker = _Tracker();
      final sharedChild = Node(
        'container',
        children: [_DependentSeed(depTracker, key: ValueKey('dep'))],
      );

      final ip =
          owner.mountRoot(
                InheritedSeed<String>(value: 'v1', child: sharedChild),
              )
              as InheritedBranch<String>;
      owner.flush();
      needsFlushCalls = 0;

      // Reach the mounted dependent branch (under the Node).
      final node = ip.childBranch! as NodeBranch;
      final dependent = node.children.single;
      expect(depTracker.builds, 1);

      // Provider value changes, child reused (identical → skipped). The
      // dependent is invalidated via dependencyChanged → scheduled → dirty.
      ip.update(InheritedSeed<String>(value: 'v2', child: sharedChild));

      expect(
        needsFlushCalls,
        1,
        reason: 'onNeedsFlush fired once on the empty→non-empty edge',
      );

      final rebuilt = owner.flush();

      expect(
        rebuilt,
        contains(dependent),
        reason:
            'A14 delta: the dependent was rebuilt BY THE DRAIN (not by a '
            'cascade), so it is INCLUDED in the returned list',
      );
      expect(
        rebuilt,
        isNot(contains(ip)),
        reason: 'the provider itself force-rebuilt during update, excluded',
      );
      expect(depTracker.builds, 2);
    });
  });

  // #6 --------------------------------------------------------------------
  group('#6 out-of-flush timing', () {
    test('a provider update outside a flush with an identical child leaves '
        'dependents dirty but not rebuilt until flush(), then they rebuild '
        'exactly once', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final depTracker = _Tracker();
      final sharedChild = Node(
        'container',
        children: [_DependentSeed(depTracker, key: ValueKey('dep'))],
      );

      final ip =
          owner.mountRoot(
                InheritedSeed<String>(value: 'v1', child: sharedChild),
              )
              as InheritedBranch<String>;
      owner.flush();
      final dependent = (ip.childBranch! as NodeBranch).children.single;
      expect(depTracker.builds, 1);

      // Update outside any flush; identical child → no cascade rebuild.
      ip.update(InheritedSeed<String>(value: 'v2', child: sharedChild));

      expect(dependent.dirty, isTrue, reason: 'scheduled but not yet rebuilt');
      expect(
        depTracker.builds,
        1,
        reason: 'no synchronous rebuild — the cascade did not run it',
      );

      owner.flush();

      expect(dependent.dirty, isFalse);
      expect(depTracker.builds, 2, reason: 'rebuilt exactly once at flush');
    });
  });

  // #7 --------------------------------------------------------------------
  group('#7 multichild reorder under identical seed', () {
    test(
      'updateChildren with a keyed child moved to a new position under an '
      'IDENTICAL seed — no rebuild, identity preserved, new order reflected',
      () {
        final owner = TreeOwner();
        addTearDown(owner.dispose);

        final trackerA = _Tracker();
        final trackerB = _Tracker();

        // Two keyed counting children; capture the exact instances.
        final seedA = _CountingSeed(trackerA);
        final keyedA = _KeyedCounting('ka', seedA);
        final keyedB = _KeyedCounting('kb', _CountingSeed(trackerB));

        final root =
            owner.mountRoot(Node('root', children: [keyedA, keyedB]))
                as NodeBranch;
        final branchA = root.children[0];
        final branchB = root.children[1];
        expect(trackerA.builds, 1);
        expect(trackerB.builds, 1);

        // Reorder: kb first, ka second — but ka is the SAME instance (identical).
        root.update(Node('root', children: [keyedB, keyedA]));

        expect(
          root.children[0].branchId,
          branchB.branchId,
          reason: 'kb moved first',
        );
        expect(
          root.children[1].branchId,
          branchA.branchId,
          reason: 'ka now second',
        );
        expect(
          root.children[1],
          same(branchA),
          reason: 'ka identity preserved',
        );
        expect(
          trackerA.builds,
          1,
          reason: 'ka reconciled against its identical seed → no rebuild',
        );
        expect(root.children.every((c) => c.mounted), isTrue);
      },
    );
  });

  // #8 --------------------------------------------------------------------
  group('#8 update() unchanged (A9 intact)', () {
    test('branch.update(sameSeedInstance) still force-rebuilds — the skip '
        'lives only in reconciliation', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final branch = owner.mountRoot(_CountingSeed(tracker)) as StatelessBranch;
      expect(tracker.builds, 1);

      final same = branch.seed;
      branch.update(same); // direct update with the identical instance

      expect(
        tracker.builds,
        2,
        reason: 'A9: update() force-rebuilds even with the same instance',
      );
    });
  });

  // #9 --------------------------------------------------------------------
  group('#9 wire-realism guard', () {
    test('two structurally-equal but DISTINCT seed instances (double '
        'deserialization) do NOT skip — the wire path gains nothing', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(const Node('root')) as NodeBranch;

      // Build with one instance; reconcile against a fresh, structurally-equal
      // but distinct instance — exactly what deserializing the same payload
      // twice produces. A counting child makes the rebuild observable.
      final s1 = _CountingSeed(tracker);
      final child = parent.updateChild(null, s1, 0)! as StatelessBranch;
      expect(tracker.builds, 1);
      final s2 = _CountingSeed(tracker); // distinct, same type, same (null) key
      expect(identical(s1, s2), isFalse, reason: 'distinct instances');

      final result = parent.updateChild(child, s2, 0);

      expect(result, same(child), reason: 'same type → updated in place');
      expect(
        tracker.builds,
        2,
        reason: 'distinct instances do NOT skip — they update() and rebuild',
      );
    });
  });

  // #10 -------------------------------------------------------------------
  group('#10 harvest conformance over a skipped subtree', () {
    test('a harvest over a tree containing a skipped subtree yields a '
        'byte-identical structural Observation', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final childTracker = _Tracker();
      // Parent re-emits the SAME cached child across rebuilds (pruned).
      final cachedChild = _CountingChildSeed(childTracker);
      final parent =
          owner.mountRoot(_CachedParentSeed(_Tracker(), cachedChild))
              as StatelessBranch;

      final before = _harvest(parent);
      expect(childTracker.builds, 1);

      // Force a parent rebuild; the child subtree is skipped.
      parent.update(_CachedParentSeed(_Tracker(), cachedChild));
      expect(childTracker.builds, 1, reason: 'child subtree pruned');

      final after = _harvest(parent);

      expect(
        after,
        equals(before),
        reason:
            'the mounted tree a harvest walks is byte-identical before and '
            'after a skipped reconcile',
      );
    });
  });
}

// --- Test-local seeds/branches used above -----------------------------------

class _HookSeed extends Seed {
  const _HookSeed();
  @override
  _HookBranch createBranch() => _HookBranch(this);
}

class _HookBranch extends Branch {
  _HookBranch(super.seed);
  int hookRuns = 0;
  @override
  void performRebuild() {
    hookRuns++;
  }
}

/// A keyed container-ish seed wrapping a single child seed, used to give #7 a
/// keyed multichild element whose own build counts.
class _KeyedCounting extends StatelessSeed {
  _KeyedCounting(String key, this.inner) : super(key: ValueKey(key));
  final Seed inner;
  @override
  Seed build(TreeContext context) => inner;
}
