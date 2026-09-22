// ignore_for_file: invalid_use_of_protected_member
// The ratified separation: Element does NOT implement BuildContext — the
// context is a separate, invalidatable capability handle. These tests make
// the fork executable: no concrete element kind is a BuildContext, and a handle
// captured in build() and held across an async gap throws StateError once its
// element unmounts.
import 'dart:async';

import 'package:test/test.dart';
import 'package:genesis_tree/genesis_tree.dart';

import 'src/fixtures.dart';

class _StatelessProbe extends StatelessComponent {
  const _StatelessProbe();
  @override
  Component build(BuildContext context) => const Leaf('stateless-child');
}

class _StatefulProbe extends StatefulComponent {
  const _StatefulProbe();
  @override
  _StatefulProbeState createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  @override
  Component build(BuildContext context) => const Leaf('stateful-child');
}

class _CaptureComponent extends StatelessComponent {
  _CaptureComponent(this.onBuild);
  final void Function(BuildContext context) onBuild;
  @override
  Component build(BuildContext context) {
    onBuild(context);
    return const Leaf('captured');
  }
}

void main() {
  group('A8: no Element implements BuildContext', () {
    test(
      'every concrete Element kind in a full tree fails `is BuildContext`',
      () {
        final owner = BuildOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(
          Node(
            'root',
            children: [
              const Leaf('bare'),
              const _StatelessProbe(),
              const _StatefulProbe(),
              InheritedComponent<String>(
                value: 'v',
                child: const _StatelessProbe(),
              ),
            ],
          ),
        );

        final all = <Element>[];
        void collect(Element element) {
          all.add(element);
          element.visitChildren(collect);
        }

        collect(root);

        // Prove the walk covered every concrete kind: container, bare leaf,
        // stateless, stateful, inherited.
        final kinds = all.map((b) => b.runtimeType.toString()).toSet();
        expect(
          kinds,
          containsAll(<String>[
            'NodeElement',
            'LeafElement',
            'StatelessElement',
            'StatefulElement',
          ]),
        );
        expect(kinds.any((k) => k.startsWith('InheritedElement')), isTrue);

        for (final element in all) {
          expect(
            element is BuildContext,
            isFalse,
            reason:
                '${element.runtimeType} must not implement BuildContext (A8: '
                'the Element≡BuildContext original sin is shed by construction)',
          );
        }
      },
    );

    test('the handle passed to build() is not a Element', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      BuildContext? captured;
      owner.mountRoot(_CaptureComponent((context) => captured = context));
      expect(captured, isNotNull);
      expect(captured, isNot(isA<Element>()));
    });
  });

  group('A8: handle validity', () {
    test('handle is live while mounted: delegates and drives rebuilds', () {
      final owner = BuildOwner();
      addTearDown(owner.dispose);
      var builds = 0;
      BuildContext? captured;
      final root = owner.mountRoot(
        _CaptureComponent((context) {
          builds++;
          captured = context;
        }),
      );

      expect(builds, 1);
      expect(captured!.mounted, isTrue);
      expect(captured!.elementId, equals(root.elementId));
      expect(captured!.key, equals(root.key));

      captured!.markNeedsRebuild();
      final rebuilt = owner.flush();
      expect(builds, 2);
      expect(rebuilt, equals([root]));
    });

    test('handle captured in build() throws StateError after its element '
        'unmounts (the async-gap case)', () async {
      final owner = BuildOwner();
      BuildContext? captured;
      owner.mountRoot(_CaptureComponent((context) => captured = context));
      final handle = captured!;
      expect(handle.mounted, isTrue);

      // The async gap: an agent reads the projection, deliberates, then
      // acts — and the tree moves under it in between.
      await Future<void>.delayed(Duration.zero);
      owner.unmountRoot();

      // `mounted` stays queryable — the safe staleness probe...
      expect(handle.mounted, isFalse);
      // ...every other capability throws.
      expect(() => handle.elementId, throwsStateError);
      expect(() => handle.key, throwsStateError);
      expect(() => handle.markNeedsRebuild(), throwsStateError);
      expect(
        () => handle.dependOnInheritedValueOfExactType<String>(),
        throwsStateError,
      );
      expect(
        () => handle.getInheritedValueOfExactType<String>(),
        throwsStateError,
      );
    });

    test('State.context is the handle, and dies with the element', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(const _StatefulProbe()) as StatefulElement;
      final context = root.state.context;
      expect(context, isNot(same(root)));
      expect(context.mounted, isTrue);

      owner.unmountRoot();

      expect(context.mounted, isFalse);
      expect(() => context.markNeedsRebuild(), throwsStateError);
    });
  });
}
