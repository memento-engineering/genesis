// The first-class Key value-type: equality/hashCode that keyed reconcile
// relies on, ObjectKey's identity semantics, the `Key(String)` ergonomic
// factory, and the deliberate absence of any cross-tree (Global) key.
//
// Equality is load-bearing: `Seed.canUpdate` and `Branch.updateChildren` match
// new config to mounted branches by `runtimeType` + key equality, so these
// laws are what make keyed identity reliable.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'src/fixtures.dart';

void main() {
  group('ValueKey equality', () {
    test('equal value + equal type parameter are equal (and hash equal)', () {
      const a = ValueKey('counter');
      const b = ValueKey('counter');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different values are not equal', () {
      expect(const ValueKey('a'), isNot(equals(const ValueKey('b'))));
    });

    test(
      'the type parameter is part of identity (no cross-type collision)',
      () {
        // The gap a bare `Object` key cannot close: 1 (int) and 1 (num) would
        // collide as map keys; as typed ValueKeys they stay distinct.
        expect(const ValueKey<int>(1), isNot(equals(const ValueKey<num>(1))));
        expect(
          const ValueKey<int>(1).hashCode,
          isNot(equals(const ValueKey<num>(1).hashCode)),
        );
      },
    );

    test('a ValueKey never equals an ObjectKey wrapping an equal value', () {
      const value = 'x';
      expect(const ValueKey(value), isNot(equals(const ObjectKey(value))));
    });

    test('toString surfaces the value for debugging', () {
      expect(const ValueKey('counter').toString(), contains('counter'));
    });
  });

  group('Key(String) factory', () {
    test('builds a ValueKey<String> equal to the explicit form', () {
      expect(const Key('id'), equals(const ValueKey<String>('id')));
      expect(const Key('id'), isA<ValueKey<String>>());
    });
  });

  group('ObjectKey identity (vs ValueKey value)', () {
    test('two distinct-but-value-equal objects: ValueKey equal, ObjectKey '
        'not', () {
      // _Tag has value equality, so the two instances are == by value but are
      // distinct objects. This is the exact case ObjectKey exists to tell
      // apart and ValueKey deliberately conflates.
      final a = _Tag(1);
      final b = _Tag(1);
      expect(a, equals(b), reason: '_Tag has value equality');

      expect(ValueKey(a), equals(ValueKey(b)), reason: 'ValueKey follows ==');
      expect(
        ObjectKey(a),
        isNot(equals(ObjectKey(b))),
        reason: 'ObjectKey follows identity, not ==',
      );
    });

    test('the same instance is equal under ObjectKey (and hash-stable)', () {
      final a = _Tag(1);
      expect(ObjectKey(a), equals(ObjectKey(a)));
      expect(ObjectKey(a).hashCode, equals(ObjectKey(a).hashCode));
    });

    test('tolerates a null value', () {
      expect(const ObjectKey(null), equals(const ObjectKey(null)));
      expect(const ObjectKey(null).toString(), contains('null'));
    });
  });

  group('keyed reconcile matches by Key value', () {
    test('value-equal keys let a child update in place (no remount)', () {
      final root =
          TreeOwner().mountRoot(
                const Node('root', children: [Leaf('a', key: ValueKey('k'))]),
              )
              as NodeBranch;
      final before = root.children.single;

      root.update(
        const Node('root', children: [Leaf('a2', key: ValueKey('k'))]),
      );

      expect(identical(root.children.single, before), isTrue);
      expect(before.mounted, isTrue);
    });

    test('a changed key forces a remount (old unmounted, new mounted)', () {
      final root =
          TreeOwner().mountRoot(
                const Node('root', children: [Leaf('a', key: ValueKey('k1'))]),
              )
              as NodeBranch;
      final before = root.children.single;

      root.update(
        const Node('root', children: [Leaf('a', key: ValueKey('k2'))]),
      );

      expect(identical(root.children.single, before), isFalse);
      expect(before.mounted, isFalse);
    });

    test('canUpdate keys on the Key value, not the seed instance', () {
      expect(
        Seed.canUpdate(
          const Leaf('a', key: ValueKey('k')),
          const Leaf('b', key: ValueKey('k')),
        ),
        isTrue,
      );
      expect(
        Seed.canUpdate(
          const Leaf('a', key: ValueKey('k')),
          const Leaf('a', key: ValueKey('other')),
        ),
        isFalse,
      );
    });
  });
}

/// A value with `==`/`hashCode` — so two distinct instances compare equal,
/// the case that separates [ValueKey] (value) from [ObjectKey] (identity).
class _Tag {
  _Tag(this.n);
  final int n;

  @override
  bool operator ==(Object other) => other is _Tag && other.n == n;

  @override
  int get hashCode => n.hashCode;
}
