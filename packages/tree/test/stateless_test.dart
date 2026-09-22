// Port of perception's stateless_perception_test.dart to tree vocabulary.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _Leaf extends Component {
  const _Leaf({super.key});
  @override
  Element createElement() => _LeafElement(this);
}

class _LeafElement extends Element {
  _LeafElement(super.component);
}

class _Tracker {
  int builds = 0;
  String? lastValue;
}

class _ReadingS extends StatelessComponent {
  _ReadingS(this.tracker);
  final _Tracker tracker;
  @override
  Component build(BuildContext context) {
    tracker.builds++;
    tracker.lastValue = context.dependOnInheritedValueOfExactType<String>();
    return const _Leaf();
  }
}

class _SimpleS extends StatelessComponent {
  const _SimpleS({this.child = const _Leaf()});
  final Component child;
  @override
  Component build(BuildContext context) => child;
}

void main() {
  test('returns StatelessElement', () {
    expect(_SimpleS().createElement(), isA<StatelessElement>());
  });

  group('BuildableElement child lifecycle', () {
    late BuildOwner owner;

    setUp(() {
      owner = BuildOwner();
    });
    tearDown(() => owner.dispose());

    test('builds its child synchronously on mount (no external dirty)', () {
      // mountRoot alone must produce the subtree — Flutter's _firstBuild.
      // No markNeedsRebuild / flush required.
      final element = owner.mountRoot(_SimpleS()) as StatelessElement;
      expect(element.child, isNotNull);
      expect(element.child!.mounted, isTrue);
    });

    test('child identity preserved across a rebuild when canUpdate=true', () {
      final element = owner.mountRoot(_SimpleS()) as StatelessElement;
      final first = element.child;

      element.markNeedsRebuild();
      owner.flush();
      expect(element.child, same(first));
    });

    test('child remounted when canUpdate=false (key change)', () {
      final element =
          owner.mountRoot(_SimpleS(child: const _Leaf(key: ValueKey('a'))))
              as StatelessElement;
      final oldChild = element.child!;
      expect(oldChild.mounted, isTrue);

      // A9 delta: update() alone now re-runs build and swaps the child
      // (ADR-0001 Decision 4); the explicit markNeedsRebuild + flush is kept
      // from the perception suite but is no longer required.
      element.update(_SimpleS(child: const _Leaf(key: ValueKey('b'))));
      element.markNeedsRebuild();
      owner.flush();

      expect(element.child, isNot(same(oldChild)));
      expect(oldChild.mounted, isFalse);
      expect(element.child!.mounted, isTrue);
    });

    test('unmounts child before clearing self', () {
      final element = owner.mountRoot(_SimpleS()) as StatelessElement;
      final child = element.child!;

      element.unmount();

      expect(child.mounted, isFalse);
      expect(element.mounted, isFalse);
    });
  });

  group('InheritedComponent + StatelessComponent headline', () {
    late BuildOwner owner;

    setUp(() {
      owner = BuildOwner();
    });
    tearDown(() => owner.dispose());

    test('reads provider on mount, re-reads after provider update', () {
      final tracker = _Tracker();
      final ipElement =
          owner.mountRoot(
                InheritedComponent<String>(
                  value: 'a',
                  child: _ReadingS(tracker),
                ),
              )
              as InheritedElement<String>;

      // Mounting drove the first build through the whole subtree — the
      // dependency on the provider is registered and 'a' was read.
      expect(tracker.builds, 1);
      expect(tracker.lastValue, 'a');

      ipElement.update(
        InheritedComponent<String>(value: 'b', child: _ReadingS(tracker)),
      );
      owner.flush();

      expect(tracker.builds, 2);
      expect(tracker.lastValue, 'b');
    });

    test('no dependent invalidation when provider value unchanged', () {
      final tracker = _Tracker();
      final ipElement =
          owner.mountRoot(
                InheritedComponent<String>(
                  value: 'a',
                  child: _ReadingS(tracker),
                ),
              )
              as InheritedElement<String>;

      expect(tracker.builds, 1);

      ipElement.update(
        InheritedComponent<String>(value: 'a', child: _ReadingS(tracker)),
      );
      // updateShouldNotify=false scheduled nothing: the flush drains empty.
      expect(owner.flush(), isEmpty);

      // A9 delta: perception expected builds == 1 here (update() swapped the
      // config without re-running builders). Under ADR-0001 Decision 4 the
      // child's config instance changed, so the update cascade re-runs
      // build() exactly once — even though updateShouldNotify is false and
      // no dependent invalidation was scheduled.
      expect(tracker.builds, 2);
    });
  });
}
