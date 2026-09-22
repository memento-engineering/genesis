// The ratified identical-component fast path.
//
// In reconciliation (Element.updateChild, and the multichild path that now
// delegates to it), an existing child reconciled against an *identical* component
// is returned untouched — no update(), no rebuild, no subtree cascade. The
// skip is identity-only (`identical()`, never `Component.operator==`) and lives in
// reconciliation only: Element.update keeps its A9 force semantics.
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

/// A stateless component that counts its build()s and returns a const child leaf.
class _CountingComponent extends StatelessComponent {
  const _CountingComponent(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    return const Leaf('counting-child');
  }
}

/// A parent whose build() returns the SAME child instance every time — either
/// a `const` (Dart-canonicalized → identical) child, or a caller-cached one.
/// Across a parent rebuild the returned child is identical, so the fast path
/// prunes the entire child subtree. The child's own builder counts via
/// [childTracker], so a re-run would be observable.
class _CachedParentComponent extends StatelessComponent {
  const _CachedParentComponent(this.parentTracker, this.cachedChild);
  final _Tracker parentTracker;
  final Component cachedChild;
  @override
  Component build(BuildContext context) {
    parentTracker.builds++;
    // Identical instance on every build → fast path skips its whole subtree.
    return cachedChild;
  }
}

/// A counting child component whose own build returns a const grandchild Leaf.
class _CountingChildComponent extends StatelessComponent {
  const _CountingChildComponent(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    return const Leaf('grandchild');
  }
}

/// A stateless component overriding ==/hashCode to VALUE equality. Two distinct
/// instances with the same `id` are `==` but not `identical` — the fast path
/// must NOT skip on these (it consults identical(), never ==).
class _ValueEqComponent extends StatelessComponent {
  const _ValueEqComponent(this.id, this.tracker);
  final String id;
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    return const Leaf('value-eq-child');
  }

  @override
  bool operator ==(Object other) =>
      other is _ValueEqComponent && other.id == id && other.tracker == tracker;

  @override
  int get hashCode => Object.hash(id, tracker);
}

/// A stateless component that reads a provided String and records each build.
class _DependentComponent extends StatelessComponent {
  _DependentComponent(this.tracker, {super.key});
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    context.dependOnInheritedValueOfExactType<String>();
    return const Leaf('dependent-child');
  }
}

/// A stateful component recording the order of didChangeDependencies / build and a
/// build count — used to prove dCD fires before build under the skip.
class _OrderComponent extends StatefulComponent {
  const _OrderComponent(this.log);
  final List<String> log;
  @override
  State<StatefulComponent> createState() => _OrderState();
}

class _OrderState extends State<_OrderComponent> {
  int builds = 0;
  @override
  void didChangeDependencies() => component.log.add('didChangeDependencies');
  @override
  Component build(BuildContext context) {
    builds++;
    component.log.add('build');
    context.dependOnInheritedValueOfExactType<String>();
    return const Leaf('order-child');
  }
}

/// A non-dependent stateless component: never reads the provider. Used to prove a
/// non-dependent sibling inside a skipped subtree never rebuilds.
class _NonDependentComponent extends StatelessComponent {
  _NonDependentComponent(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    return const Leaf('non-dependent-child');
  }
}

/// Walks a mounted subtree depth-first and renders a stable structural
/// snapshot (the shape a perception harvest would observe): component tag + ordered
/// children. Two trees with the same shape produce byte-identical strings.
String _harvest(Element element) {
  final buffer = StringBuffer();
  void walk(Element b) {
    final component = b.component;
    final tag = component is Leaf
        ? 'Leaf(${component.tag})'
        : '${component.runtimeType}'
              '${component.key != null ? '#${component.key}' : ''}';
    buffer.write('<$tag>');
    b.visitChildren(walk);
    buffer.write('</>');
  }

  walk(element);
  return buffer.toString();
}

void main() {
  // #1 --------------------------------------------------------------------
  group('#1 skip-on-identical', () {
    test(
      'updateChild with an identical component returns the same element and does '
      'NOT re-run the child build (build counter stays put)',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final tracker = _Tracker();
        final parent =
            owner.mountRoot(_CountingComponent(tracker)) as StatelessElement;
        final child = parent.child!;
        expect(tracker.builds, 1, reason: 'one build on mount');

        // Reconcile the parent's child against the SAME instance it already
        // holds: identical → skip.
        final result = parent.updateChild(child, child.component, 0);

        expect(result, same(child), reason: 'same element returned as-is');
        expect(
          tracker.builds,
          1,
          reason: 'the fast path skipped update()/rebuild — no rebuild ran',
        );
      },
    );

    test('a bare hook element is not rebuilt when reconciled with its own '
        'identical component (performRebuild does not run)', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const Node('root')) as NodeElement;
      final hook = _HookElement(const _HookComponent())..mount(root, 0);
      expect(hook.hookRuns, 0);

      final result = root.updateChild(hook, hook.component, 0);

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
        're-run; element identity preserved', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final parentTracker = _Tracker();
      final childTracker = _Tracker();
      // A single cached child instance (the const-canonicalized / prebuilt
      // pattern): identical across the parent's two builds → pruned.
      final cachedChild = _CountingChildComponent(childTracker);
      final parent =
          owner.mountRoot(_CachedParentComponent(parentTracker, cachedChild))
              as StatelessElement;
      expect(parentTracker.builds, 1);
      expect(
        childTracker.builds,
        1,
        reason: 'child + grandchild built once on mount',
      );
      final childElement = parent.child!;

      // Force the parent to rebuild with a fresh (non-identical) parent component:
      // its build() re-runs and re-emits the SAME child instance, which the
      // fast path then prunes — child + grandchild builders do not re-run.
      parent.update(_CachedParentComponent(parentTracker, cachedChild));

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
        same(childElement),
        reason: 'child identity preserved',
      );
    });
  });

  // #3 --------------------------------------------------------------------
  group('#3 identity-not-value', () {
    test('a component with value-equality ==/hashCode STILL rebuilds when a '
        'distinct-but-==-equal component arrives — the skip uses identical(), not '
        '==', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(const Node('root')) as NodeElement;

      final a = _ValueEqComponent('same', tracker);
      final child = parent.updateChild(null, a, 0)! as StatelessElement;
      expect(tracker.builds, 1);

      final b = _ValueEqComponent('same', tracker);
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
      final owner = BuildOwner();
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
          _DependentComponent(depTracker, key: ValueKey('dep')),
          _NonDependentComponent(nonDepTracker),
          _OrderComponent(orderLog),
        ],
      );

      final ip =
          owner.mountRoot(
                InheritedComponent<String>(value: 'v1', child: sharedChild),
              )
              as InheritedElement<String>;
      // First flush settles the initial subtree build.
      owner.flush();
      expect(depTracker.builds, 1);
      expect(nonDepTracker.builds, 1);
      expect(orderLog, equals(['didChangeDependencies', 'build']));

      orderLog.clear();

      // New provider config: changed value, SAME child instance (identical →
      // the child subtree reconcile is skipped). Dependents are invalidated
      // through dependencyChanged independently of the skip.
      ip.update(InheritedComponent<String>(value: 'v2', child: sharedChild));
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
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      var needsFlushCalls = 0;
      owner.onNeedsFlush = () => needsFlushCalls++;

      final depTracker = _Tracker();
      final sharedChild = Node(
        'container',
        children: [_DependentComponent(depTracker, key: ValueKey('dep'))],
      );

      final ip =
          owner.mountRoot(
                InheritedComponent<String>(value: 'v1', child: sharedChild),
              )
              as InheritedElement<String>;
      owner.flush();
      needsFlushCalls = 0;

      // Reach the mounted dependent element (under the Node).
      final node = ip.childElement! as NodeElement;
      final dependent = node.children.single;
      expect(depTracker.builds, 1);

      // Provider value changes, child reused (identical → skipped). The
      // dependent is invalidated via dependencyChanged → scheduled → dirty.
      ip.update(InheritedComponent<String>(value: 'v2', child: sharedChild));

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
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      final depTracker = _Tracker();
      final sharedChild = Node(
        'container',
        children: [_DependentComponent(depTracker, key: ValueKey('dep'))],
      );

      final ip =
          owner.mountRoot(
                InheritedComponent<String>(value: 'v1', child: sharedChild),
              )
              as InheritedElement<String>;
      owner.flush();
      final dependent = (ip.childElement! as NodeElement).children.single;
      expect(depTracker.builds, 1);

      // Update outside any flush; identical child → no cascade rebuild.
      ip.update(InheritedComponent<String>(value: 'v2', child: sharedChild));

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
  group('#7 multichild reorder under identical component', () {
    test(
      'updateChildren with a keyed child moved to a new position under an '
      'IDENTICAL component — no rebuild, identity preserved, new order reflected',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);

        final trackerA = _Tracker();
        final trackerB = _Tracker();

        // Two keyed counting children; capture the exact instances.
        final seedA = _CountingComponent(trackerA);
        final keyedA = _KeyedCounting('ka', seedA);
        final keyedB = _KeyedCounting('kb', _CountingComponent(trackerB));

        final root =
            owner.mountRoot(Node('root', children: [keyedA, keyedB]))
                as NodeElement;
        final branchA = root.children[0];
        final branchB = root.children[1];
        expect(trackerA.builds, 1);
        expect(trackerB.builds, 1);

        // Reorder: kb first, ka second — but ka is the SAME instance (identical).
        root.update(Node('root', children: [keyedB, keyedA]));

        expect(
          root.children[0].elementId,
          branchB.elementId,
          reason: 'kb moved first',
        );
        expect(
          root.children[1].elementId,
          branchA.elementId,
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
          reason: 'ka reconciled against its identical component → no rebuild',
        );
        expect(root.children.every((c) => c.mounted), isTrue);
      },
    );
  });

  // #8 --------------------------------------------------------------------
  group('#8 update() unchanged (A9 intact)', () {
    test('element.update(sameSeedInstance) still force-rebuilds — the skip '
        'lives only in reconciliation', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final element =
          owner.mountRoot(_CountingComponent(tracker)) as StatelessElement;
      expect(tracker.builds, 1);

      final same = element.component;
      element.update(same); // direct update with the identical instance

      expect(
        tracker.builds,
        2,
        reason: 'A9: update() force-rebuilds even with the same instance',
      );
    });
  });

  // #9 --------------------------------------------------------------------
  group('#9 wire-realism guard', () {
    test('two structurally-equal but DISTINCT component instances (double '
        'deserialization) do NOT skip — the wire path gains nothing', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final tracker = _Tracker();
      final parent = owner.mountRoot(const Node('root')) as NodeElement;

      // Build with one instance; reconcile against a fresh, structurally-equal
      // but distinct instance — exactly what deserializing the same payload
      // twice produces. A counting child makes the rebuild observable.
      final s1 = _CountingComponent(tracker);
      final child = parent.updateChild(null, s1, 0)! as StatelessElement;
      expect(tracker.builds, 1);
      final s2 = _CountingComponent(
        tracker,
      ); // distinct, same type, same (null) key
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
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      final childTracker = _Tracker();
      // Parent re-emits the SAME cached child across rebuilds (pruned).
      final cachedChild = _CountingChildComponent(childTracker);
      final parent =
          owner.mountRoot(_CachedParentComponent(_Tracker(), cachedChild))
              as StatelessElement;

      final before = _harvest(parent);
      expect(childTracker.builds, 1);

      // Force a parent rebuild; the child subtree is skipped.
      parent.update(_CachedParentComponent(_Tracker(), cachedChild));
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

// --- Test-local seeds/elements used above -----------------------------------

class _HookComponent extends Component {
  const _HookComponent();
  @override
  _HookElement createElement() => _HookElement(this);
}

class _HookElement extends Element {
  _HookElement(super.component);
  int hookRuns = 0;
  @override
  void performRebuild() {
    hookRuns++;
  }
}

/// A keyed container-ish component wrapping a single child component, used to give #7 a
/// keyed multichild element whose own build counts.
class _KeyedCounting extends StatelessComponent {
  _KeyedCounting(String key, this.inner) : super(key: ValueKey(key));
  final Component inner;
  @override
  Component build(BuildContext context) => inner;
}
