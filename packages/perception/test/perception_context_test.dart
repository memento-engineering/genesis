// PerceptionContext — the capability extension of TreeContext (A8 × A12):
// the domain layers harvest vocabulary onto the separate handle, inheriting
// the executable async-gap protection.
import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _P extends Perception {
  const _P({super.key});
  @override
  _E createElement() => _E(this);
}

class _E extends PerceptionElement {
  _E(super.p);
  int harvests = 0;
  @override
  void markNeedsHarvest() {
    harvests++;
    super.markNeedsHarvest();
  }
}

class _CapturingP extends StatelessPerception {
  _CapturingP(this.captured);
  final List<PerceptionContext> captured;
  @override
  Seed build(PerceptionContext context) {
    captured.add(context);
    return const _P();
  }
}

void main() {
  group('PerceptionContext capability handle', () {
    test('element context is a PerceptionContext, never the element (A8)', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(_P()) as _E;

      expect(el.context, isA<PerceptionContext>());
      expect(el.context, isNot(same(el)));
      expect(el.context, isNot(isA<Branch>()));
    });

    test('handle is canonical — same instance per element', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(_P()) as _E;
      expect(el.context, same(el.context));
    });

    test('perceptionId aliases branchId; key surfaces the seed key', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(_P(key: 'k')) as _E;
      final context = el.context;
      expect(context.perceptionId, equals(el.branchId));
      expect(context.branchId, equals(el.branchId));
      expect(context.key, equals('k'));
    });

    test('markNeedsHarvest via handle routes through the element funnel and '
        'schedules a harvest', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(_P()) as _E;

      el.context.markNeedsHarvest();

      expect(el.harvests, equals(1));
      expect(owner.flushHarvest(), equals([el]));
    });

    test('after unmount: mounted stays queryable, every other member throws '
        'StateError (executable async-gap protection)', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(_P()) as _E;
      final context = el.context;

      owner.unmountRoot();

      expect(context.mounted, isFalse);
      expect(() => context.perceptionId, throwsStateError);
      expect(() => context.branchId, throwsStateError);
      expect(() => context.key, throwsStateError);
      expect(
        () => context.dependOnInheritedSeedOfExactType<String>(),
        throwsStateError,
      );
      expect(() => context.markNeedsHarvest(), throwsStateError);
      expect(() => context.markNeedsRebuild(), throwsStateError);
    });

    test('StatelessPerception.build receives the PerceptionContext handle', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final captured = <PerceptionContext>[];
      final el =
          owner.mountRoot(_CapturingP(captured)) as StatelessPerceptionElement;

      expect(captured, hasLength(1));
      expect(captured.single, same(el.context));
      expect(captured.single.perceptionId, equals(el.branchId));
    });
  });
}
