# genesis_foundation

The layer **below** the spine: a dependency-free diagnostics protocol and the
typed, versioned wire contract that carries it off-process.

`genesis_foundation` sits under [`genesis_tree`](https://pub.dev/packages/genesis_tree)
the way Flutter's `foundation` sits under `widgets` — the tree depends on it,
never the reverse. It has **no runtime dependencies at all**, so a consumer that
only needs to read diagnostics (a DevTools extension, a dashboard, a log
renderer) can depend on this package alone and never pull in a tree engine.

## The protocol

Objects describe *themselves*. There is no central projector that has to know
about every type.

| Type | Role |
| --- | --- |
| `Diagnosticable` | Mixin. Override `debugFillProperties` to contribute your own properties; get `toStringDeep()` for free. |
| `DiagnosticableTree` | Adds `debugDescribeChildren()` for tree-shaped nodes, so `toStringDeep()` recurses. |

```dart
class Widget with Diagnosticable {
  Widget(this.label, this.enabled);
  final String label;
  final bool enabled;

  @override
  void debugFillProperties(List<DiagnosticsProperty> properties) {
    properties
      ..add(DiagnosticsProperty.string(name: 'label', value: label))
      ..add(DiagnosticsProperty.flag(name: 'enabled', value: enabled));
  }
}
```

Adding a new type makes it diagnosable on the spot — nothing outside the type
needs editing.

## The properties

`DiagnosticsProperty` is a sealed union, so a `switch` over it is
compiler-checked and a new variant forces every consumer to handle it. Each
property carries a `DiagnosticsLevel` (`fine`, `info`, `warning`, `error`), so a
dirty-stuck node or an errored fragment can be surfaced by severity rather than
by string-matching a dump.

Variants cover `string`, `int`, `double`, `flag`, `enumValue`, `duration`,
`timestamp` and `object`.

## The wire contract

`TreeSnapshot` is the serialized form for out-of-process consumers: a
`contractVersion`, a `projectedAt` timestamp, and a `TreeNode` root carrying
properties and children.

This is a deliberate divergence from Flutter, whose inspector ships an untyped
`Map<String, Object?>` over the wire. A typed, versioned snapshot lets a client
parse with the compiler's help and detect a contract it is too old to read.

## Conventions

Value types here are **hand-written** — const constructors, `==`, `hashCode`,
`copyWith`, and hand-rolled version-1 JSON codecs — rather than generated. That
is permanent for the foundation and the spine, not a workaround: this package
must stay dependency-free, and the spine must not take on a codegen toolchain.
Exhaustive `switch` expressions remain the house style.

## Where this sits

```
genesis_foundation   Diagnosticable · DiagnosticsProperty · TreeSnapshot
        ▲
genesis_tree         Seed / Branch — the keyed-reconcile spine
        ▲
genesis_perception   measurement domain on the spine
```

Part of [genesis](https://github.com/memento-engineering/genesis).
