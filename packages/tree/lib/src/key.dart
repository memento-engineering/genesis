import 'package:meta/meta.dart';

/// A first-class identity token for a `Seed`, used by keyed reconciliation to
/// pair a new configuration with an existing mounted `Branch` across rebuilds.
///
/// A `Key` is the reconciliation identity: `Seed.canUpdate` and
/// `Branch.updateChildren` match by `runtimeType` + key equality, so a key
/// must define value `==`/`hashCode` (every concrete key here does). Reusing
/// the same key on the same position across a re-emission keeps the branch —
/// and its state — alive instead of tearing it down and rebuilding.
///
/// Two concrete kinds ship on the spine:
///
/// - [ValueKey] — keyed by a value's `==`/`hashCode` (the common case; the
///   unnamed [Key] factory builds a `ValueKey<String>`).
/// - [ObjectKey] — keyed by the *identity* of an object, for when two equal-by-
///   value objects must still be told apart.
///
/// `Key` is intentionally **open** (abstract, not sealed): the spine ships the
/// two common kinds, and domains/consumers (e.g. `the_grid`, or the render
/// layer's render-scope key) define their own `Key` subtypes by extending it
/// and supplying `==`/`hashCode`. The reconciler only ever consults key
/// equality, so any well-behaved subtype slots in.
///
/// ## Deliberately no `GlobalKey`
///
/// Flutter's `Key` hierarchy has a `GlobalKey` that enables cross-tree lookup
/// (find *any* element anywhere by its key, reparent across the tree). genesis
/// **refuses that** by design: there is no `GlobalKey`, and no global key
/// registry. Cross-boundary references (e.g. a workflow step that `needs`
/// another) pass handles down through the parent, keeping the tree one-way and
/// honest — a branch can be reached only by walking from a root, never by a
/// hidden global side-channel. If a genuine global-lookup need ever appears it
/// must be a separate, explicit, opt-in mechanism, never the default `Key`.
///
/// Because there is no `GlobalKey`, Flutter's intermediate `LocalKey` layer
/// (whose sole job is to separate local keys from global ones) would be
/// vacuous here, so it is omitted: every `Key` is local by construction, and
/// the concrete kinds extend `Key` directly.
@immutable
abstract class Key {
  /// Constructs a [ValueKey] that matches on the equality of the given string.
  ///
  /// This is the ergonomic default for the overwhelmingly common string-keyed
  /// case (`key: const Key('counter')` is `ValueKey<String>('counter')`).
  const factory Key(String value) = ValueKey<String>;

  /// Const constructor for subclasses. The unnamed [Key] constructor is a
  /// factory, so subclasses chain to this instead (`: super.empty()`).
  @protected
  const Key.empty();
}

/// A [Key] backed by a [value] of type [T]; equal when both the runtime type
/// and the value are equal.
///
/// `ValueKey<int>(1)` and `ValueKey<num>(1)` are distinct — the type parameter
/// is part of identity — which is exactly the "no accidental cross-type
/// collision" guarantee a bare `Object` key cannot give.
class ValueKey<T> extends Key {
  /// Creates a key that delegates its identity to [value]'s `==`/`hashCode`.
  const ValueKey(this.value) : super.empty();

  /// The value this key matches on.
  final T value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is ValueKey<T> && other.value == value;
  }

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() {
    final valueString = T == String ? "<'$value'>" : '<$value>';
    return '[ValueKey<$T> $valueString]';
  }
}

/// A [Key] backed by the *identity* of [value]; equal only when both keys wrap
/// the identical (`identical`) object.
///
/// Use this when value equality is too coarse — two distinct objects that
/// compare equal by `==` must still be reconciled as separate children
/// (Flutter's classic example: keying list rows by the model object itself so
/// equal-looking entries stay distinct).
class ObjectKey extends Key {
  /// Creates a key that matches on the identity of [value].
  const ObjectKey(this.value) : super.empty();

  /// The object this key matches on by identity.
  final Object? value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is ObjectKey && identical(other.value, value);
  }

  @override
  int get hashCode => Object.hash(runtimeType, identityHashCode(value));

  @override
  String toString() {
    final type = value == null ? 'null' : value.runtimeType.toString();
    final id = value == null
        ? ''
        : '#${identityHashCode(value).toRadixString(16)}';
    return '[ObjectKey $type$id]';
  }
}
