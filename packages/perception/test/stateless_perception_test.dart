// Conformance port of lenny perception's stateless_perception_test.dart
// (A10 gate). Two tests carry A9 deltas (ADR-0001 Decision 4) — see
// docs/CONFORMANCE-DELTA.md.
import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _Leaf extends Perception {
  const _Leaf({super.key});
  @override
  PerceptionElement createElement() => _LeafElement(this);
}

class _LeafElement extends PerceptionElement {
  _LeafElement(super.p);
}

class _Tracker {
  int builds = 0;
  String? lastValue;
}

class _ReadingP extends StatelessPerception {
  _ReadingP(this.tracker);
  final _Tracker tracker;
  @override
  Seed build(PerceptionContext context) {
    tracker.builds++;
    tracker.lastValue = context.dependOnInheritedSeedOfExactType<String>();
    return const _Leaf();
  }
}

class _SimpleP extends StatelessPerception {
  const _SimpleP({this.child = const _Leaf()});
  final Seed child;
  @override
  Seed build(PerceptionContext context) => child;
}

void main() {
  test('returns StatelessPerceptionElement', () {
    expect(_SimpleP().createBranch(), isA<StatelessPerceptionElement>());
  });

  group('ComponentBranch child lifecycle', () {
    late PerceptionOwner owner;

    setUp(() {
      owner = PerceptionOwner();
    });
    tearDown(() => owner.dispose());

    test('builds its child synchronously on mount (no external dirty)', () {
      // mountRoot alone must produce the subtree — Flutter's _firstBuild.
      // No markNeedsHarvest / flushHarvest required.
      final el = owner.mountRoot(_SimpleP()) as StatelessPerceptionElement;
      expect(el.child, isNotNull);
      expect(el.child!.mounted, isTrue);
    });

    test('child identity preserved across a rebuild when canUpdate=true', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessPerceptionElement;
      final first = el.child;

      el.markNeedsRebuild();
      owner.flushHarvest();
      expect(el.child, same(first));
    });

    test('child remounted when canUpdate=false (key change)', () {
      final el =
          owner.mountRoot(_SimpleP(child: const _Leaf(key: 'a')))
              as StatelessPerceptionElement;
      final oldChild = el.child!;
      expect(oldChild.mounted, isTrue);

      // A9 delta: update() alone now re-runs build and swaps the child
      // (ADR-0001 Decision 4); the explicit markNeedsRebuild + flushHarvest
      // is kept from the lenny suite but is no longer required.
      el.update(_SimpleP(child: const _Leaf(key: 'b')));
      el.markNeedsRebuild();
      owner.flushHarvest();

      expect(el.child, isNot(same(oldChild)));
      expect(oldChild.mounted, isFalse);
      expect(el.child!.mounted, isTrue);
    });

    test('unmounts child before clearing self', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessPerceptionElement;
      final child = el.child!;

      el.unmount();

      expect(child.mounted, isFalse);
      expect(el.mounted, isFalse);
    });
  });

  group('InheritedPerception + StatelessPerception headline', () {
    late PerceptionOwner owner;

    setUp(() {
      owner = PerceptionOwner();
    });
    tearDown(() => owner.dispose());

    test('reads provider on mount, re-reads after provider update', () {
      final tracker = _Tracker();
      final ipEl =
          owner.mountRoot(
                InheritedPerception<String>(
                  value: 'a',
                  child: _ReadingP(tracker),
                ),
              )
              as InheritedPerceptionElement<String>;

      // Mounting drove the first build through the whole subtree — the
      // dependency on the provider is registered and 'a' was read.
      expect(tracker.builds, 1);
      expect(tracker.lastValue, 'a');

      ipEl.update(
        InheritedPerception<String>(value: 'b', child: _ReadingP(tracker)),
      );
      owner.flushHarvest();

      expect(tracker.builds, 2);
      expect(tracker.lastValue, 'b');
    });

    test('no dependent invalidation when provider value unchanged', () {
      final tracker = _Tracker();
      final ipEl =
          owner.mountRoot(
                InheritedPerception<String>(
                  value: 'a',
                  child: _ReadingP(tracker),
                ),
              )
              as InheritedPerceptionElement<String>;

      expect(tracker.builds, 1);

      ipEl.update(
        InheritedPerception<String>(value: 'a', child: _ReadingP(tracker)),
      );
      // updateShouldNotify=false scheduled nothing: the flush drains empty.
      expect(owner.flushHarvest(), isEmpty);

      // A9 delta: lenny expected builds == 1 here (update() swapped the
      // config without re-running builders). Under ADR-0001 Decision 4 the
      // child's config instance changed, so the update cascade re-runs
      // build() exactly once — even though updateShouldNotify is false and
      // no dependent invalidation was scheduled.
      expect(tracker.builds, 2);
    });
  });
}
