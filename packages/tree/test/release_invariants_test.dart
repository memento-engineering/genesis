// The four pre-existing tree guards this file covers throw in RELEASE builds,
// not only under assertions. The mid-flush dirty-ancestry order guard is
// deliberately assertion-only. This file is therefore run both ways:
//   dart test test/release_invariants_test.dart   (assertions ON)
//   dart run  test/release_invariants_test.dart   (assertions OFF)
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

bool get _assertionsEnabled {
  var enabled = false;
  assert(enabled = true);
  return enabled;
}

class _SiblingDirtyComponent extends Component {
  const _SiblingDirtyComponent();

  @override
  _SiblingDirtyElement createElement() => _SiblingDirtyElement(this);
}

class _SiblingDirtyElement extends Element {
  _SiblingDirtyElement(super.component);

  Element? dirtyTarget;
  int buildCount = 0;

  @override
  void performRebuild() {
    buildCount++;
    dirtyTarget?.markNeedsRebuild();
  }
}

/// A stateful component whose build calls setState — the pathological case that
/// drained forever in release.
class _SetStateDuringBuild extends StatefulComponent {
  const _SetStateDuringBuild();

  @override
  State<_SetStateDuringBuild> createState() => _SetStateDuringBuildState();
}

class _SetStateDuringBuildState extends State<_SetStateDuringBuild> {
  int _count = 0;

  @override
  Component build(BuildContext context) {
    setState(() => _count++);
    return Leaf('count-$_count');
  }
}

/// A leaf that records its own unmount into [log] — the lifecycle probe that
/// proves the duplicate-key guard runs before any mutation.
class _Probe extends Component {
  _Probe(this.tag, this.log, {super.key});

  final String tag;
  final List<String> log;

  @override
  _ProbeElement createElement() => _ProbeElement(this);
}

class _ProbeElement extends Element {
  _ProbeElement(_Probe super.component);

  @override
  void unmount() {
    log.add((component as _Probe).tag);
    super.unmount();
  }

  List<String> get log => (component as _Probe).log;
}

class _RetainedContext {
  BuildContext? value;
}

class _RetainedContextComponent extends StatefulComponent {
  const _RetainedContextComponent(this.retainedContext);

  final _RetainedContext retainedContext;

  @override
  State<_RetainedContextComponent> createState() => _RetainedContextState();
}

class _RetainedContextState extends State<_RetainedContextComponent> {
  @override
  Component build(BuildContext context) {
    component.retainedContext.value = context;
    return const Leaf('retained-context-child');
  }
}

void main() {
  test('setState during build throws StateError from flush and the drain '
      'terminates', () {
    final owner = BuildOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const _SetStateDuringBuild());

    expect(
      owner.flush,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('element ${root.elementId}'),
            contains('setState during build'),
          ),
        ),
      ),
    );
    expect(owner.flush(), isEmpty);
  });

  test('sibling dirty during build is rejected only under assertions', () {
    final owner = BuildOwner();
    addTearDown(owner.dispose);
    final root =
        owner.mountRoot(
              const Node(
                'root',
                children: [_SiblingDirtyComponent(), _SiblingDirtyComponent()],
              ),
            )
            as NodeElement;
    final source = root.children[0] as _SiblingDirtyElement;
    final target = root.children[1] as _SiblingDirtyElement;
    source.dirtyTarget = target;
    source.markNeedsRebuild();

    if (_assertionsEnabled) {
      expect(
        owner.flush,
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('element ${target.elementId}'),
              contains('element ${source.elementId}'),
              contains('descendant'),
            ),
          ),
        ),
      );
      expect(target.buildCount, 0);
    } else {
      expect(owner.flush(), orderedEquals([source, target]));
      expect(target.buildCount, 1);
    }
  });

  test('duplicate sibling keys throw before any old element is unmounted', () {
    final owner = BuildOwner();
    addTearDown(owner.dispose);
    final log = <String>[];
    final root =
        owner.mountRoot(
              Node(
                'parent',
                children: [
                  _Probe('a', log, key: const ValueKey('k1')),
                  _Probe('b', log, key: const ValueKey('k2')),
                ],
              ),
            )
            as NodeElement;
    final before = List<Element>.of(root.children);

    expect(
      () => root.update(
        Node(
          'parent',
          children: [
            _Probe('a', log, key: const ValueKey('dup')),
            _Probe('b', log, key: const ValueKey('dup')),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('Duplicate child key'), contains('dup')),
        ),
      ),
    );

    expect(log, isEmpty, reason: 'no old element may be unmounted');
    expect(before.every((b) => b.mounted), isTrue);
    expect(root.children, orderedEquals(before));
  });

  test('Element.update with an incompatible component throws StateError', () {
    final owner = BuildOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const Leaf('a', key: ValueKey('a')));

    expect(
      () => root.update(const Leaf('a', key: ValueKey('b'))),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('canUpdate'),
        ),
      ),
    );
  });

  test(
    'retained BuildContext rejects dependency registration outside every tree phase',
    () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      final retainedContext = _RetainedContext();
      final provider =
          owner.mountRoot(
                InheritedComponent<int>(
                  value: 7,
                  child: _RetainedContextComponent(retainedContext),
                ),
              )
              as InheritedElement<int>;
      final element = provider.childElement as StatefulElement;

      expect(provider.dependents, isEmpty);
      expect(element.dependencies, isEmpty);
      expect(
        () => retainedContext.value!.dependOnInheritedValueOfExactType<int>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'dependOnInheritedValueOfExactType<int>() called outside a tree '
                'lifecycle phase (TreeLifecyclePhase.notInTreePhase). '
                'Register inherited dependencies from '
                'didChangeDependencies() or build().',
          ),
        ),
      );
      expect(provider.dependents, isEmpty);
      expect(element.dependencies, isEmpty);
    },
  );
}
