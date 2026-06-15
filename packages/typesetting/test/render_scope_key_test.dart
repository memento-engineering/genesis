// Locks the render-scope key invariant: a render container wraps each child to
// thread the render-parent link, and that wrapper must NOT shadow the child's
// own key. If it did, a key-based tree lookup (e.g. an action router resolving
// an A2UI component id to its single branch) would find two branches for one
// id. These tests assert one-branch-per-key under Stage/Box AND that keyed
// reconcile through the wrapper still preserves identity across a reorder.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

void main() {
  group('render-scope key does not shadow the child key', () {
    test('exactly one mounted branch answers to each child key under a '
        'render container', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(
        Stage(
          width: 40,
          height: 12,
          sink: _NullSink(),
          children: [
            Box(
              title: 'panel',
              key: 'b1',
              children: [Text('hello', key: 't1')],
            ),
          ],
        ),
      );

      final mounted = _walk(root);

      // The component branches each answer to their key exactly once — the
      // render-scope wrappers carry a distinct, namespaced key.
      expect(_countKey(mounted, 'b1'), 1, reason: 'Box branch keyed b1');
      expect(_countKey(mounted, 't1'), 1, reason: 'Text branch keyed t1');

      // Sanity: the keyed branch found for each id is the real render branch,
      // not an inherited-value wrapper.
      expect(_branchKeyed(mounted, 'b1'), isA<RenderBranch>());
      expect(_branchKeyed(mounted, 't1'), isA<RenderBranch>());
    });

    test('keyed children directly under the Stage are single-keyed', () {
      final owner = TreeOwner();
      final root = owner.mountRoot(
        Stage(
          width: 40,
          height: 12,
          sink: _NullSink(),
          children: [
            Text('a', key: 'x1'),
            Text('b', key: 'x2'),
          ],
        ),
      );

      final mounted = _walk(root);
      expect(_countKey(mounted, 'x1'), 1);
      expect(_countKey(mounted, 'x2'), 1);
    });
  });

  test('keyed reconcile through the render scope preserves identity across a '
      'reorder', () {
    final owner = TreeOwner();
    final sink = _NullSink();
    Stage scene(List<Seed> kids) =>
        Stage(width: 40, height: 12, sink: sink, children: kids);

    final root = owner.mountRoot(
      scene([Box(title: 'A', key: 'a'), Box(title: 'B', key: 'b')]),
    );

    final beforeA = _branchKeyed(_walk(root), 'a');
    final beforeB = _branchKeyed(_walk(root), 'b');

    // Reorder the two keyed children. Keyed reconcile must move each branch to
    // its new slot WITHOUT remounting — proving the namespaced wrapper key
    // still drives correct keyed matching.
    root.update(scene([Box(title: 'B', key: 'b'), Box(title: 'A', key: 'a')]));

    final afterA = _branchKeyed(_walk(root), 'a');
    final afterB = _branchKeyed(_walk(root), 'b');

    expect(identical(beforeA, afterA), isTrue, reason: 'Box a kept its branch');
    expect(identical(beforeB, afterB), isTrue, reason: 'Box b kept its branch');
    expect(afterA.mounted, isTrue);
    expect(afterB.mounted, isTrue);
  });
}

/// Collects every mounted branch in [root]'s subtree, root first.
List<Branch> _walk(Branch root) {
  final out = <Branch>[];
  void visit(Branch b) {
    out.add(b);
    b.visitChildren(visit);
  }

  visit(root);
  return out;
}

int _countKey(List<Branch> branches, Object key) =>
    branches.where((b) => b.mounted && b.key == key).length;

Branch _branchKeyed(List<Branch> branches, Object key) =>
    branches.firstWhere((b) => b.mounted && b.key == key);

/// A byte sink that discards everything — these tests assert on tree shape,
/// not emitted frames.
class _NullSink implements Sink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void close() {}
}
