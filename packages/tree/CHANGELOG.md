# Changelog

## 0.1.3

- **Breaking:** a first-class `Key` value-type. `Seed.key` (and `Branch.key`,
  `TreeContext.key`) is now typed `Key?` instead of `Object?`. Two concrete
  kinds ship: `ValueKey<T>(value)` (value equality; the type parameter is part
  of identity, so `ValueKey<int>(1) != ValueKey<num>(1)`) and `ObjectKey(value)`
  (identity equality), plus an ergonomic `const Key(String)` factory that builds
  a `ValueKey<String>`. The typed key gives reconciliation identity intent and
  type-safety and a shared identity story for keyed list reconcile.
- `Key` is **open** (abstract, not sealed): domains extend it with their own key
  kinds. There is deliberately **no `GlobalKey`** — cross-tree lookup is refused
  so the tree stays one-way (cross-boundary references pass handles through the
  parent) — and no `LocalKey` layer (vacuous without a global key).
- Migration: replace `key: 'id'` with `key: ValueKey('id')` (or `Key('id')`),
  and `seed.key == 'id'` comparisons with `seed.key == ValueKey('id')`.

## 0.1.2

- Add a debug assertion that sibling keys are unique within `updateChildren`
  (debug-mode only; surfaces duplicate-key reconcile bugs earlier, no
  release-mode behavior change).

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev.
- Reworded the `TreeContext` use-after-unmount `StateError` message (text only; no behavior change).

## 0.1.0

- Initial release: the Seed/Branch keyed-reconcile engine — TreeContext (a separate capability handle), TreeOwner, the composition layer (Stateless/Stateful/State, InheritedSeed, Watch, Sprout), and the identical-config skip fast path.

  Pre-1.0 and experimental; APIs may change before 1.0.
