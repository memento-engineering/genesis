// Conformance port of lenny perception's watch_test.dart (A10 gate).
// Watch<T> is consumed via the tree re-export (register A13: Watch lives in
// tree's composition layer); structural assertions use tree types.
import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:test/test.dart';

class _Leaf extends Perception {
  const _Leaf(this.tag);
  final String tag;
  @override
  _LeafElement createElement() => _LeafElement(this);
}

class _LeafElement extends PerceptionElement {
  _LeafElement(super.p);
}

void main() {
  group('Watch<T> structure', () {
    test('createBranch returns StatefulBranch with WatchState', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final w = Watch<int>(
        ctrl.stream,
        (_) => const _Leaf('x'),
        initialValue: 0,
      );
      final el = w.createBranch();
      expect(el, isA<StatefulBranch>());
      // mount to initialise state
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(w) as StatefulBranch;
      expect(root.state, isA<WatchState<int>>());
    });
  });

  group('Watch<T> initial value', () {
    test('builder called with initialValue before any stream emit', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);

      final built = <int>[];
      owner.mountRoot(
        Watch<int>(ctrl.stream, (v) {
          built.add(v);
          return const _Leaf('x');
        }, initialValue: 42),
      );

      expect(built, equals([42]));
    });
  });

  group('Watch<T> stream emit', () {
    test('builder called with new value after emit', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);

      final built = <int>[];
      owner.mountRoot(
        Watch<int>(ctrl.stream, (v) {
          built.add(v);
          return const _Leaf('x');
        }, initialValue: 0),
      );

      built.clear();
      ctrl.add(10);
      owner.flushHarvest();
      expect(built, equals([10]));
    });

    test('multiple emits each trigger rebuild with latest value', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);

      final built = <int>[];
      owner.mountRoot(
        Watch<int>(ctrl.stream, (v) {
          built.add(v);
          return const _Leaf('x');
        }, initialValue: 0),
      );

      built.clear();
      ctrl.add(1);
      owner.flushHarvest();
      ctrl.add(2);
      owner.flushHarvest();
      ctrl.add(3);
      owner.flushHarvest();
      expect(built, equals([1, 2, 3]));
    });
  });

  group('Watch<T> cancel on dispose', () {
    test('no rebuild after unmount — subscription cancelled', () {
      final ctrl = StreamController<int>(sync: true);
      addTearDown(ctrl.close);
      final owner = PerceptionOwner();

      int buildCount = 0;
      owner.mountRoot(
        Watch<int>(ctrl.stream, (v) {
          buildCount++;
          return const _Leaf('x');
        }, initialValue: 0),
      );

      buildCount = 0;
      owner.unmountRoot();

      ctrl.add(99);
      expect(buildCount, equals(0));
    });
  });

  group('Watch<T> pure Dart', () {
    test('no flutter import — guard via dart analyze', () async {
      // Compile-time check: dart analyze passes without flutter dependency
      // (full guard: no_flutter_test.dart + melos run analyze at repo root)
      expect(true, isTrue); // sentinel — real check is the purity guard
    });
  });
}
