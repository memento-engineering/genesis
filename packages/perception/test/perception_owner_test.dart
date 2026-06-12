// Conformance port of lenny perception's perception_owner_test.dart
// (A10 gate). Behavior expectations unchanged; flushHarvest now also returns
// the rebuilt elements (ADR-0001 Decision 5), asserted where it strengthens
// the original.
import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

class _FakeP extends Perception {
  const _FakeP({this.childConfig});
  final Perception? childConfig;
  @override
  _FakeE createElement() => _FakeE(this);
}

class _FakeE extends PerceptionElement {
  _FakeE(_FakeP super.p);
  int buildCount = 0;
  Branch? childEl;

  @override
  void performRebuild() {
    buildCount++;
    final child = (perception as _FakeP).childConfig;
    childEl = updateChild(childEl, child, 0);
  }
}

class _SideEffectP extends Perception {
  const _SideEffectP();
  @override
  _SideEffectE createElement() => _SideEffectE(this);
}

class _SideEffectE extends PerceptionElement {
  _SideEffectE(super.p);
  int buildCount = 0;
  void Function()? sideEffect;

  @override
  void performRebuild() {
    buildCount++;
    sideEffect?.call();
  }
}

class _RedirtyP extends Perception {
  const _RedirtyP();
  @override
  _RedirtyE createElement() => _RedirtyE(this);
}

class _RedirtyE extends PerceptionElement {
  _RedirtyE(super.p);

  @override
  void performRebuild() {
    markNeedsHarvest(); // pathological: re-dirty self on every rebuild
  }
}

class _ObservingP extends Perception {
  const _ObservingP();
  @override
  _ObservingE createElement() => _ObservingE(this);
}

class _ObservingE extends PerceptionElement {
  _ObservingE(super.p);
  int? lastValue;

  @override
  void performRebuild() {
    lastValue = dependOnInheritedSeedOfExactType<int>();
  }
}

void main() {
  group('PerceptionOwner.mountRoot', () {
    test('assigns owner to root element before mount', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP()) as _FakeE;
      expect(root.owner, same(owner));
      expect(root.depth, 0);
      owner.dispose();
    });

    test('child mounted via updateChild inherits owner and depth=1', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP(childConfig: _FakeP())) as _FakeE;
      root.performRebuild(); // mounts child
      expect(root.childEl?.owner, same(owner));
      expect(root.childEl?.depth, 1);
      owner.dispose();
    });

    test('throws if mountRoot called twice', () {
      final owner = PerceptionOwner();
      owner.mountRoot(_FakeP());
      expect(() => owner.mountRoot(_FakeP()), throwsA(isA<AssertionError>()));
      owner.dispose();
    });
  });

  group('markNeedsHarvest scheduling + onNeedsHarvest', () {
    test('fires onNeedsHarvest exactly once on empty->non-empty', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP()) as _FakeE;
      int fired = 0;
      owner.onNeedsHarvest = () => fired++;

      root.markNeedsHarvest();
      root.markNeedsHarvest(); // idempotent — already dirty
      expect(fired, 1);
      owner.dispose();
    });

    test('fires again after flush empties dirty set', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP()) as _FakeE;
      int fired = 0;
      owner.onNeedsHarvest = () => fired++;

      root.markNeedsHarvest();
      owner.flushHarvest();
      root.markNeedsHarvest();
      expect(fired, 2);
      owner.dispose();
    });
  });

  group('flushHarvest', () {
    test(
      'end-to-end: InheritedPerception value change -> rebuild reads new value',
      () {
        final owner = PerceptionOwner();
        final fakeP = _ObservingP();
        final root = owner.mountRoot(
          InheritedPerception<int>(value: 5, child: fakeP),
        );
        final ipEl = root as InheritedPerceptionElement<int>;
        final fakeEl = ipEl.childBranch as _ObservingE;
        fakeEl.performRebuild(); // register dependency
        root.update(InheritedPerception<int>(value: 7, child: fakeP));
        owner.flushHarvest();
        expect(fakeEl.lastValue, 7);
        owner.dispose();
      },
    );

    test(
      'depth ordering: parent rebuilt before child, no redundant child rebuild',
      () {
        final owner = PerceptionOwner();
        final child = _FakeP();
        final root = owner.mountRoot(_FakeP(childConfig: child)) as _FakeE;
        root.performRebuild(); // establish child
        final childEl = root.childEl! as _FakeE;

        root.markNeedsHarvest();
        childEl.markNeedsHarvest();

        final rootBuildsBefore = root.buildCount;
        final childBuildsBefore = childEl.buildCount;
        owner.flushHarvest();
        // Root must have been rebuilt exactly once during flush
        expect(root.buildCount - rootBuildsBefore, 1);
        // Child at most once — depth ordering prevents redundant rebuild
        // (under A9, the root's reconcile force-rebuilds the child once and
        // clears its dirty flag, so the drain skips it).
        expect(childEl.buildCount - childBuildsBefore, lessThanOrEqualTo(1));
        owner.dispose();
      },
    );

    test(
      'dirty-during-flush: element dirtied mid-flush is rebuilt in same pass',
      () {
        final owner = PerceptionOwner();
        final root = owner.mountRoot(_SideEffectP()) as _SideEffectE;
        // Mount a target as a child of root so it inherits the owner
        final target = _FakeP().createElement();
        target.mount(root, 0);

        // root's performRebuild will dirty target mid-flush
        root.sideEffect = () => target.markNeedsHarvest();
        root.markNeedsHarvest();

        owner.flushHarvest();

        expect(root.buildCount, 1);
        expect(
          target.buildCount,
          1,
        ); // dirtied mid-flush; rebuilt in the same pass
        owner.dispose();
      },
    );

    test(
      'pathological re-dirty: performRebuild re-dirties self throws AssertionError',
      () {
        final owner = PerceptionOwner();
        final root = owner.mountRoot(_RedirtyP()) as _RedirtyE;
        root.markNeedsHarvest();
        expect(() => owner.flushHarvest(), throwsA(isA<AssertionError>()));
        owner.dispose();
      },
    );

    test('flushHarvest is a no-op when dirty set is empty', () {
      final owner = PerceptionOwner();
      owner.mountRoot(_FakeP());
      expect(() => owner.flushHarvest(), returnsNormally);
      expect(owner.flushHarvest(), isEmpty);
      owner.dispose();
    });

    test('flushHarvest returns the rebuilt elements in flush order', () {
      // ADR-0001 Decision 5: the drained dirty set is exposed to backends.
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP()) as _FakeE;
      root.markNeedsHarvest();
      expect(owner.flushHarvest(), equals([root]));
      owner.dispose();
    });
  });

  group('dispose / unmountRoot', () {
    test('unmountRoot unmounts the root element', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP());
      owner.unmountRoot();
      expect(root.mounted, isFalse);
    });

    test('dispose unmounts root and clears dirty set', () {
      final owner = PerceptionOwner();
      final root = owner.mountRoot(_FakeP()) as _FakeE;
      root.markNeedsHarvest();
      owner.dispose();
      expect(root.mounted, isFalse);
    });
  });
}
