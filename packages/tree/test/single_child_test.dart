// SingleChildSeed (stateless + stateful) and Nest — the vertical single-child
// chain vocabulary. MultiChildSeed fans out horizontally; Nest stacks a list of
// wrapping seeds top-to-bottom down to one leaf. These tests pin: chain order,
// standalone use, inherited-value visibility through the chain, downstream/leaf
// change propagation through identical intermediate links, stateful state
// persistence + dispose, node-type-change remount, and the identical-Nest skip.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

// Build counter for the identical-skip proof. Reset per test.
int _wrapBuilds = 0;

/// A stateless single-child link that wraps its downstream in a `Node` tagged
/// [tag], so a tree walk can read the chain order.
class _Wrap extends SingleChildStatelessSeed {
  const _Wrap(this.tag, {super.child});
  final String tag;
  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    _wrapBuilds++;
    return Node(tag, children: [child]);
  }
}

/// A stateless link that provides a `String` to its downstream via
/// `InheritedSeed`, to prove ambient lookup works through the chain.
class _Provide extends SingleChildStatelessSeed {
  const _Provide(this.value);
  final String value;
  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      InheritedSeed<String>(value: value, child: child);
}

// The value the most recent _Consumer saw.
String? _seenValue;

/// A leaf that reads the ambient `String` and records it.
class _Consumer extends StatelessSeed {
  const _Consumer();
  @override
  Seed build(TreeContext context) {
    _seenValue = context.dependOnInheritedSeedOfExactType<String>();
    return const Leaf('consumer');
  }
}

// The live state of the most recently mounted _Counter.
_CounterState? _capturedCounter;

/// A stateful single-child link whose count a test can drive, wrapping its
/// downstream in a `Node` tagged with the current count.
class _Counter extends SingleChildStatefulSeed {
  const _Counter({super.child});
  @override
  _CounterState createState() => _CounterState();
}

class _CounterState extends SingleChildState<_Counter> {
  int n = 0;
  bool disposed = false;

  @override
  void initState() {
    super.initState();
    _capturedCounter = this;
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      Node('counter:$n', children: [child]);

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  void bump() => setState(() => n++);
}

// Top-down labels for the linear spine: `node:<name>` for each Node, `leaf:<tag>`
// for each Leaf, in tree order. Link/component branches carry no label.
List<String> _labels(Branch root) {
  final out = <String>[];
  void walk(Branch b) {
    final s = b.seed;
    if (s is Node) out.add('node:${s.name}');
    if (s is Leaf) out.add('leaf:${s.tag}');
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

void main() {
  late TreeOwner owner;
  setUp(() {
    owner = TreeOwner();
    _wrapBuilds = 0;
    _seenValue = null;
    _capturedCounter = null;
  });
  tearDown(() => owner.dispose());

  group('Nest — chain composition', () {
    test('empty children mounts the leaf directly', () {
      final root =
          owner.mountRoot(const Nest(children: [], child: Leaf('leaf')))
              as NestBranch;
      expect(root.head, isA<LeafBranch>());
      expect((root.head!.seed as Leaf).tag, 'leaf');
    });

    test('stacks children outermost-first down to the leaf', () {
      final root =
          owner.mountRoot(
                const Nest(
                  children: [_Wrap('a'), _Wrap('b'), _Wrap('c')],
                  child: Leaf('z'),
                ),
              )
              as NestBranch;
      expect(_labels(root), ['node:a', 'node:b', 'node:c', 'leaf:z']);
    });

    test('an ambient value from an upper link is visible below it', () {
      owner.mountRoot(
        const Nest(
          children: [_Provide('hello'), _Wrap('mid')],
          child: _Consumer(),
        ),
      );
      expect(_seenValue, 'hello');
    });
  });

  group('Nest — reconcile', () {
    test('a leaf change propagates through identical intermediate links', () {
      const a = _Wrap('a');
      const b = _Wrap('b');
      final root =
          owner.mountRoot(const Nest(children: [a, b], child: Leaf('first')))
              as NestBranch;
      expect(_labels(root), ['node:a', 'node:b', 'leaf:first']);

      // Same link instances, new leaf: the fresh-carrier refold carries the
      // change past the (identical) a/b links.
      root.update(const Nest(children: [a, b], child: Leaf('second')));
      expect(_labels(root), ['node:a', 'node:b', 'leaf:second']);
    });

    test('an identical Nest is skipped — the chain is not rebuilt', () {
      const nest = Nest(children: [_Wrap('a')], child: Leaf('x'));
      final host =
          owner.mountRoot(const Node('host', children: [nest])) as NodeBranch;
      expect(_wrapBuilds, 1);

      // Reconcile the host against the SAME nest instance: updateChild's
      // identical-skip prunes the whole chain before NestBranch rebuilds.
      host.update(const Node('host', children: [nest]));
      expect(_wrapBuilds, 1, reason: 'identical Nest -> chain not rebuilt');
    });
  });

  group('Nest — stateful links', () {
    test('setState rebuilds the link in place', () {
      final root =
          owner.mountRoot(const Nest(children: [_Counter()], child: Leaf('x')))
              as NestBranch;
      expect(_labels(root), ['node:counter:0', 'leaf:x']);

      _capturedCounter!.bump();
      owner.flush();
      expect(_labels(root), ['node:counter:1', 'leaf:x']);
    });

    test('state persists across a Nest rebuild', () {
      const counter = _Counter();
      final root =
          owner.mountRoot(const Nest(children: [counter], child: Leaf('x')))
              as NestBranch;
      _capturedCounter!.bump();
      owner.flush();
      final state = _capturedCounter!;

      // Rebuild the Nest with a new leaf; the link branch persists, so its
      // state (n == 1) survives and only the leaf changes.
      root.update(const Nest(children: [counter], child: Leaf('y')));
      expect(identical(_capturedCounter, state), isTrue);
      expect(_labels(root), ['node:counter:1', 'leaf:y']);
    });

    test('a node-type change at a position remounts (fresh state)', () {
      final root =
          owner.mountRoot(const Nest(children: [_Counter()], child: Leaf('x')))
              as NestBranch;
      final first = _capturedCounter!;
      first.bump();
      owner.flush();

      // Swap the stateful link for a stateless one at the same position: the
      // carrier key changes, so the old link unmounts (disposed) and remounts.
      root.update(const Nest(children: [_Wrap('a')], child: Leaf('x')));
      expect(first.disposed, isTrue);
      expect(_labels(root), ['node:a', 'leaf:x']);
    });

    test('unmounting the Nest disposes the link state', () {
      owner.mountRoot(const Nest(children: [_Counter()], child: Leaf('x')));
      final state = _capturedCounter!;
      expect(state.disposed, isFalse);

      owner.unmountRoot();
      expect(state.disposed, isTrue);
    });
  });

  group('standalone single-child seeds', () {
    test('a stateless single-child seed wraps its own child', () {
      final root =
          owner.mountRoot(const _Wrap('solo', child: Leaf('leaf')))
              as SingleChildStatelessBranch;
      expect(_labels(root), ['node:solo', 'leaf:leaf']);
    });

    test('a stateful single-child seed wraps its own child', () {
      final root =
          owner.mountRoot(const _Counter(child: Leaf('leaf')))
              as SingleChildStatefulBranch;
      expect(_labels(root), ['node:counter:0', 'leaf:leaf']);
    });

    test('a single-child seed with no child throws on build', () {
      expect(
        () => owner.mountRoot(const _Wrap('x')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
