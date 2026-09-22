// Build-owner scheduling and flush coverage.
import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

class _FakeS extends Component {
  const _FakeS({this.childConfig});
  final Component? childConfig;
  @override
  _FakeB createElement() => _FakeB(this);
}

class _FakeB extends Element {
  _FakeB(_FakeS super.component);
  int buildCount = 0;
  Element? childElement;

  @override
  void performRebuild() {
    buildCount++;
    final child = (component as _FakeS).childConfig;
    childElement = updateChild(childElement, child, 0);
  }
}

class _RedirtyS extends Component {
  const _RedirtyS();
  @override
  _RedirtyB createElement() => _RedirtyB(this);
}

class _RedirtyB extends Element {
  _RedirtyB(super.component);

  @override
  void performRebuild() {
    markNeedsRebuild(); // pathological: re-dirty self on every rebuild
  }
}

class _ObservingS extends Component {
  const _ObservingS();
  @override
  _ObservingB createElement() => _ObservingB(this);
}

class _ObservingB extends Element {
  _ObservingB(super.component);
  int? lastValue;

  @override
  void performRebuild() {
    lastValue = dependOnInheritedValueOfExactType<int>();
  }
}

class _CascadeComponent extends Component {
  const _CascadeComponent();

  @override
  _CascadeElement createElement() => _CascadeElement(this);
}

class _CascadeElement extends Element {
  _CascadeElement(super.component);

  final List<Element> _children = [];
  List<Component> nextChildSeeds = const [];
  void Function()? postReconcile;
  int buildCount = 0;

  List<Element> get mountedChildren => List.unmodifiable(_children);

  @override
  void performRebuild() {
    buildCount++;
    final updated = updateChildren(_children, nextChildSeeds);
    _children
      ..clear()
      ..addAll(updated);
    postReconcile?.call();
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    _children.forEach(visitor);
  }

  @override
  void unmount() {
    for (final child in _children.reversed) {
      child.unmount();
    }
    _children.clear();
    super.unmount();
  }
}

void main() {
  group('BuildOwner.mountRoot', () {
    test('assigns owner to root element before mount', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS()) as _FakeB;
      expect(root.owner, same(owner));
      expect(root.depth, 0);
      owner.dispose();
    });

    test('child mounted via updateChild inherits owner and depth=1', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS(childConfig: _FakeS())) as _FakeB;
      root.performRebuild(); // mounts child
      expect(root.childElement?.owner, same(owner));
      expect(root.childElement?.depth, 1);
      owner.dispose();
    });

    test('throws if mountRoot called twice', () {
      final owner = BuildOwner();
      owner.mountRoot(_FakeS());
      expect(() => owner.mountRoot(_FakeS()), throwsA(isA<AssertionError>()));
      owner.dispose();
    });
  });

  group('scheduleRebuildFor + onNeedsFlush', () {
    test('fires onNeedsFlush exactly once on empty->non-empty', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS()) as _FakeB;
      int fired = 0;
      owner.onNeedsFlush = () => fired++;

      root.markNeedsRebuild();
      root.markNeedsRebuild(); // idempotent — already dirty
      expect(fired, 1);
      owner.dispose();
    });

    test('fires again after flush empties dirty set', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS(childConfig: _FakeS())) as _FakeB;
      root.performRebuild();
      final child = root.childElement!;
      int fired = 0;
      owner.onNeedsFlush = () => fired++;

      child.markNeedsRebuild();
      owner.flush();
      root.markNeedsRebuild();
      expect(fired, 2);
      owner.dispose();
    });
  });

  group('flush', () {
    test(
      'end-to-end: InheritedComponent value change -> rebuild reads new value',
      () {
        final owner = BuildOwner();
        final fakeS = _ObservingS();
        final root = owner.mountRoot(
          InheritedComponent<int>(value: 5, child: fakeS),
        );
        final ipElement = root as InheritedElement<int>;
        final fakeElement = ipElement.childElement as _ObservingB;
        fakeElement.performRebuild(); // register dependency
        root.update(InheritedComponent<int>(value: 7, child: fakeS));
        owner.flush();
        expect(fakeElement.lastValue, 7);
        owner.dispose();
      },
    );

    test(
      'depth ordering: parent rebuilt before child, no redundant child rebuild',
      () {
        final owner = BuildOwner();
        final child = _FakeS();
        final root = owner.mountRoot(_FakeS(childConfig: child)) as _FakeB;
        root.performRebuild(); // establish child
        final childElement = root.childElement! as _FakeB;

        root.markNeedsRebuild();
        childElement.markNeedsRebuild();

        final rootBuildsBefore = root.buildCount;
        final childBuildsBefore = childElement.buildCount;
        owner.flush();
        // Root must have been rebuilt exactly once during flush
        expect(root.buildCount - rootBuildsBefore, 1);
        // Child at most once — depth ordering prevents redundant rebuild
        // (under A9, the root's reconcile force-rebuilds the child once and
        // clears its dirty flag, so the drain skips it).
        expect(
          childElement.buildCount - childBuildsBefore,
          lessThanOrEqualTo(1),
        );
        owner.dispose();
      },
    );

    test('restored root may dirty an identical-skipped descendant', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(const _CascadeComponent()) as _CascadeElement;
      root.nextChildSeeds = [_CascadeComponent(), _CascadeComponent()];
      root.rebuild(force: true);
      final first = root.mountedChildren[0] as _CascadeElement;
      final target = root.mountedChildren[1] as _CascadeElement;

      root.nextChildSeeds = [_CascadeComponent(), target.component];
      root.postReconcile = target.markNeedsRebuild;
      root.markNeedsRebuild();

      final rebuilt = owner.flush();

      expect(first.buildCount, 1, reason: 'the first child was force-updated');
      expect(target.buildCount, 1);
      expect(rebuilt, orderedEquals([root, target]));
      expect(root.mountedChildren.every((child) => child.mounted), isTrue);
      owner.dispose();
    });

    test('deeper cousin dirty from a later cascade sibling is rejected', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(const _CascadeComponent()) as _CascadeElement;
      root.nextChildSeeds = [_CascadeComponent(), _CascadeComponent()];
      root.rebuild(force: true);
      final first = root.mountedChildren[0] as _CascadeElement;
      final laterSibling = root.mountedChildren[1] as _CascadeElement;
      first.nextChildSeeds = [_CascadeComponent()];
      first.rebuild(force: true);
      final target = first.mountedChildren.single as _CascadeElement;

      // The depth-2 target is force-updated earlier in this same cascade. It
      // would look valid against the depth-0 drained root, but it is not a
      // descendant of the later depth-1 sibling whose build dirties it.
      first.nextChildSeeds = [_CascadeComponent()];
      laterSibling.postReconcile = target.markNeedsRebuild;
      root.nextChildSeeds = [_CascadeComponent(), _CascadeComponent()];
      root.markNeedsRebuild();

      expect(
        owner.flush,
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('element ${target.elementId}'),
              contains('element ${laterSibling.elementId}'),
              contains('descendant'),
              contains('may not be visited in this flush pass'),
            ),
          ),
        ),
      );
      expect(target.buildCount, 1, reason: 'already updated in this cascade');
      owner.dispose();
    });

    test(
      'pathological re-dirty: performRebuild re-dirties self throws StateError',
      () {
        final owner = BuildOwner();
        final root = owner.mountRoot(_RedirtyS());
        root.markNeedsRebuild();
        expect(() => owner.flush(), throwsA(isA<StateError>()));
        owner.dispose();
      },
    );

    test('flush is a no-op when dirty set is empty', () {
      final owner = BuildOwner();
      owner.mountRoot(_FakeS());
      expect(() => owner.flush(), returnsNormally);
      expect(owner.flush(), isEmpty);
      owner.dispose();
    });
  });

  group('dispose / unmountRoot', () {
    test('unmountRoot unmounts the root element', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS());
      owner.unmountRoot();
      expect(root.mounted, isFalse);
    });

    test('dispose unmounts root and clears dirty set', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(_FakeS());
      root.markNeedsRebuild();
      owner.dispose();
      expect(root.mounted, isFalse);
    });
  });
}
