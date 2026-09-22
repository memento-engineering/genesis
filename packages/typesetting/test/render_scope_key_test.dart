// Locks the render-scope key invariant: a render container wraps each child to
// thread the render-parent link, and that wrapper must NOT shadow the child's
// own key. If it did, a key-based tree lookup (e.g. an action router resolving
// an A2UI component id to its single element) would find two elements for one
// id. These tests assert one-element-per-key under Stage/Box AND that keyed
// reconcile through the wrapper still preserves identity across a reorder.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

void main() {
  group('render-scope key does not shadow the child key', () {
    test('exactly one mounted element answers to each child key under a '
        'render container', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Stage(
          width: 40,
          height: 12,
          sink: _NullSink(),
          children: [
            Box(
              title: 'panel',
              key: ValueKey('b1'),
              children: [Text('hello', key: ValueKey('t1'))],
            ),
          ],
        ),
      );

      final mounted = _walk(root);

      // The component elements each answer to their key exactly once — the
      // render-scope wrappers carry a distinct, namespaced key.
      expect(_countKey(mounted, 'b1'), 1, reason: 'Box element keyed b1');
      expect(_countKey(mounted, 't1'), 1, reason: 'Text element keyed t1');

      // Sanity: the keyed element found for each id is the real render element,
      // not an inherited-value wrapper.
      expect(_branchKeyed(mounted, 'b1'), isA<RenderElement>());
      expect(_branchKeyed(mounted, 't1'), isA<RenderElement>());
    });

    test('keyed children directly under the Stage are single-keyed', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Stage(
          width: 40,
          height: 12,
          sink: _NullSink(),
          children: [
            Text('a', key: ValueKey('x1')),
            Text('b', key: ValueKey('x2')),
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
    final owner = BuildOwner();
    final sink = _NullSink();
    Stage scene(List<Component> kids) =>
        Stage(width: 40, height: 12, sink: sink, children: kids);

    final root = owner.mountRoot(
      scene([
        Box(title: 'A', key: ValueKey('a')),
        Box(title: 'B', key: ValueKey('b')),
      ]),
    );

    final beforeA = _branchKeyed(_walk(root), 'a');
    final beforeB = _branchKeyed(_walk(root), 'b');

    // Reorder the two keyed children. Keyed reconcile must move each element to
    // its new slot WITHOUT remounting — proving the namespaced wrapper key
    // still drives correct keyed matching.
    root.update(
      scene([
        Box(title: 'B', key: ValueKey('b')),
        Box(title: 'A', key: ValueKey('a')),
      ]),
    );

    final afterA = _branchKeyed(_walk(root), 'a');
    final afterB = _branchKeyed(_walk(root), 'b');

    expect(
      identical(beforeA, afterA),
      isTrue,
      reason: 'Box a kept its element',
    );
    expect(
      identical(beforeB, afterB),
      isTrue,
      reason: 'Box b kept its element',
    );
    expect(afterA.mounted, isTrue);
    expect(afterB.mounted, isTrue);
  });
}

/// Collects every mounted element in [root]'s subtree, root first.
List<Element> _walk(Element root) {
  final out = <Element>[];
  void visit(Element b) {
    out.add(b);
    b.visitChildren(visit);
  }

  visit(root);
  return out;
}

int _countKey(List<Element> elements, String id) =>
    elements.where((b) => b.mounted && b.key == ValueKey(id)).length;

Element _branchKeyed(List<Element> elements, String id) =>
    elements.firstWhere((b) => b.mounted && b.key == ValueKey(id));

/// A byte sink that discards everything — these tests assert on tree shape,
/// not emitted frames.
class _NullSink implements Sink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void close() {}
}
