/// Render-parent threading (the RenderObject.parent analog, register A23),
/// flow layout v1, and keyed reorder — the render-tree structure suite.
///
/// Threading is asserted as explicit render-tree adjacency: render branches
/// separated by Watch/Stateless wrappers (and perception's Node) still
/// attach to the right render parent, exactly as RenderObjectWidgets
/// compose across component widgets.
library;

import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

/// A Stateless layer wrapping another Stateless layer wrapping a [Box] —
/// two component branches between the stage and the box.
class _LayeredBox extends StatelessSeed {
  const _LayeredBox({required this.title});

  final String title;

  @override
  Seed build(TreeContext context) => _InnerLayer(title: title);
}

class _InnerLayer extends StatelessSeed {
  const _InnerLayer({required this.title});

  final String title;

  @override
  Seed build(TreeContext context) => Box(
    title: title,
    children: [_LayeredLine(content: '$title body')],
  );
}

/// A Stateless layer between a [Box] and its [Text] line.
class _LayeredLine extends StatelessSeed {
  const _LayeredLine({required this.content});

  final String content;

  @override
  Seed build(TreeContext context) => Text(content);
}

void main() {
  group('render-parent threading', () {
    test('render branches separated by Stateless wrappers attach to the '
        'right render parent (explicit adjacency)', () {
      final owner = TreeOwner();
      final stage =
          owner.mountRoot(
                Stage(
                  width: 30,
                  height: 8,
                  sink: RecordingSink(),
                  children: const [_LayeredBox(title: 'layered')],
                ),
              )
              as StageBranch;

      // Downward adjacency: stage -> box -> text, across the wrappers.
      expect(stage.renderChildren, hasLength(1));
      final box = stage.renderChildren.single;
      expect(box, isA<BoxBranch>());
      expect(box.renderChildren, hasLength(1));
      final line = box.renderChildren.single;
      expect(line, isA<TextBranch>());

      // Upward adjacency (the RenderObject.parent analog).
      expect(identical(box.renderParent, stage), isTrue);
      expect(identical(line.renderParent, box), isTrue);
      expect(stage.renderParent, isNull, reason: 'the stage is the root');

      // The TREE adjacency is NOT direct: component branches intervene.
      final treeChildren = <Branch>[];
      stage.visitChildren(treeChildren.add);
      expect(
        treeChildren.single,
        isNot(isA<RenderBranch>()),
        reason:
            'the stage\'s direct tree child is the scope wrapper, '
            'not the box — threading crossed intervening branches',
      );

      owner.dispose();
    });

    test('render branches under a perception Node attach across it', () {
      final owner = TreeOwner();
      final stage =
          owner.mountRoot(
                Stage(
                  width: 30,
                  height: 10,
                  sink: RecordingSink(),
                  children: const [
                    Node(
                      'group',
                      children: [
                        Box(title: 'a', key: 'a'),
                        Box(title: 'b', key: 'b'),
                      ],
                    ),
                  ],
                ),
              )
              as StageBranch;

      final found = stage.renderChildren;
      expect(found, hasLength(2));
      for (final box in found) {
        expect(
          identical(box.renderParent, stage),
          isTrue,
          reason: 'perception Node must be transparent to the render tree',
        );
      }

      owner.dispose();
    });

    test('a component rebuild that swaps its render child re-attaches the '
        'replacement (the dynamic attachRenderObject case)', () async {
      final toggle = StreamController<bool>();
      final owner = TreeOwner();
      final stage =
          owner.mountRoot(
                Stage(
                  width: 30,
                  height: 8,
                  sink: RecordingSink(),
                  children: [
                    Watch<bool>(
                      toggle.stream,
                      (boxed) => boxed
                          ? const Box(title: 'boxed')
                          : const Text('bare'),
                      initialValue: true,
                    ),
                  ],
                ),
              )
              as StageBranch;

      final before = stage.renderChildren.single;
      expect(before, isA<BoxBranch>());
      expect(identical(before.renderParent, stage), isTrue);

      toggle.add(false); // Box -> Text: unmount + fresh mount mid-flush
      await pumpEventQueue();

      final after = stage.renderChildren.single;
      expect(after, isA<TextBranch>());
      expect(
        identical(after.renderParent, stage),
        isTrue,
        reason:
            'the freshly mounted render branch must find its render '
            'parent without the container\'s reconcile in the call stack',
      );
      expect(
        before.renderParent,
        isNull,
        reason: 'the dropped child is unlinked',
      );
      expect(before.mounted, isFalse);

      owner.dispose();
      await toggle.close();
    });
  });

  group('flow layout v1', () {
    test('stage stacks boxes; boxes stack text lines (rects + render '
        'snapshot)', () {
      final owner = TreeOwner();
      final stage =
          owner.mountRoot(
                Stage(
                  width: 20,
                  height: 10,
                  sink: RecordingSink(),
                  children: const [
                    Box(title: 'a', children: [Text('one'), Text('two')]),
                    Box(title: 'b', children: [Text('three')]),
                  ],
                ),
              )
              as StageBranch;

      final boxA = stage.renderChildren[0];
      final boxB = stage.renderChildren[1];
      expect(boxA.rect, const Rect.fromLTWH(0, 0, 20, 4));
      expect(boxA.renderChildren[0].rect, const Rect.fromLTWH(2, 1, 16, 1));
      expect(boxA.renderChildren[1].rect, const Rect.fromLTWH(2, 2, 16, 1));
      expect(boxB.rect, const Rect.fromLTWH(0, 4, 20, 3));
      expect(boxB.renderChildren[0].rect, const Rect.fromLTWH(2, 5, 16, 1));

      expect(stage.grid.frontToString().trimRight(), '''
┌─ a ──────────────┐
│ one              │
│ two              │
└──────────────────┘
┌─ b ──────────────┐
│ three            │
└──────────────────┘''');

      owner.dispose();
    });
  });

  group('keyed reorder', () {
    test('reordering keyed boxes moves the render tree and preserves '
        'branch identity', () async {
      final order = StreamController<List<String>>();
      final owner = TreeOwner();
      final stage =
          owner.mountRoot(
                Stage(
                  width: 20,
                  height: 8,
                  sink: RecordingSink(),
                  children: [
                    Watch<List<String>>(
                      order.stream,
                      (keys) => Node(
                        'boxes',
                        children: [
                          for (final k in keys)
                            Box(
                              title: k,
                              key: k,
                              children: [Text('$k line', key: 'line')],
                            ),
                        ],
                      ),
                      initialValue: const ['alpha', 'beta'],
                    ),
                  ],
                ),
              )
              as StageBranch;

      final alphaBefore = stage.renderChildren[0];
      final betaBefore = stage.renderChildren[1];
      expect((alphaBefore.seed as Box).title, 'alpha');
      expect((betaBefore.seed as Box).title, 'beta');
      expect(alphaBefore.rect, const Rect.fromLTWH(0, 0, 20, 3));
      expect(betaBefore.rect, const Rect.fromLTWH(0, 3, 20, 3));

      order.add(const ['beta', 'alpha']);
      await pumpEventQueue();

      // The render tree follows the new order...
      final first = stage.renderChildren[0];
      final second = stage.renderChildren[1];
      expect((first.seed as Box).title, 'beta');
      expect((second.seed as Box).title, 'alpha');
      // ...with branch identity preserved across the move...
      expect(identical(first, betaBefore), isTrue);
      expect(identical(second, alphaBefore), isTrue);
      expect(identical(first.renderParent, stage), isTrue);
      expect(identical(second.renderParent, stage), isTrue);
      // ...and the rects swapped by relayout.
      expect(first.rect, const Rect.fromLTWH(0, 0, 20, 3));
      expect(second.rect, const Rect.fromLTWH(0, 3, 20, 3));

      expect(stage.grid.frontToString().trimRight(), '''
┌─ beta ───────────┐
│ beta line        │
└──────────────────┘
┌─ alpha ──────────┐
│ alpha line       │
└──────────────────┘''');

      owner.dispose();
      await order.close();
    });
  });
}
