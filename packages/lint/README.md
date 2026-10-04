# genesis_lint

Static analysis rules that keep `BuildContext` capabilities scoped safely and
keep tree code declarative: a build describes children, effects live in
leaves, and configuration is read from the tree rather than cached or
constructed bare. This package is an analyzer extension; applications do not
import it at runtime, and it deliberately has no dependency on `genesis_tree`
or `genesis_foundation`. Rules match the resolved declaring-library URI of the
types and annotations they inspect, so a same-named type or annotation from
another package is never matched.

Analyzer extensions are available on Dart 3.10 and later. Enable this one in
the top-level `plugins` section of a package-root or workspace-root
`analysis_options.yaml`:

```yaml
plugins:
  genesis_lint: ^0.3.0-dev.1
```

For local development, replace the version with a path dependency:

```yaml
plugins:
  genesis_lint:
    path: packages/lint
```

Every diagnostic is a warning, so each is enabled without a `diagnostics`
mapping. None of them reports in a package's `test/` directory.

## `no_stored_tree_context`

Rejects a `BuildContext` assigned to durable object state, inserted into a
collection, or captured by an escaping closure. The ban is unconditional:
checking `mounted` does not make retaining a write-capability handle on a
long-lived unmanaged object safe. Framework storage owned by a `Element` or a
`BuildContext` implementation is exempt.

## `use_tree_context_synchronously`

Rejects a `BuildContext` use after `await` unless the same handle has had an
intervening `mounted` probe. Holding the handle across an asynchronous gap is
legal when it is checked before use:

```dart
Future<void> rebuildLater(BuildContext context) async {
  await waitForWork();
  if (!context.mounted) return;
  context.markNeedsRebuild();
}
```

A second `await` invalidates the earlier probe and requires another check.

## `no_effects_in_build`

Rejects an effect inside the `build` (or `buildWithChild`) of a
`genesis_tree` `Component` or `State` subclass: an invocation whose static
type is `Future` or `FutureOr`, a `Timer` construction or static call,
`scheduleMicrotask`, `setState`, `await`, and an assignment or `++`/`--` to
anything but a local variable — a field of `this` or of any other object, a
top-level or static variable, or an index into a non-local collection.
Constructing components and filling local collections stay legal. A closure
or local function that the build only hands on (a callback, an effect hook)
is not checked; one invoked on the spot is.

```dart
@override
Component build(BuildContext context) => switch (phase) {
  Idle() => const Waiting(),
  Running(:final command) => Spawn(command: command),
};
```

The process starts in `Spawn`'s Element, not in the build that emits it.

## `no_cached_dependency`

Rejects a `??=` into a field, top-level variable or property whose right-hand
side calls a member on a `BuildContext` — `dependOnInheritedValueOfExactType`,
`getInheritedValueOfExactType`, `watch`, `read` — or passes a `BuildContext`
to any invocation. The cache freezes the first value it saw, so a change to
the provided value never propagates. A `??=` into a local is not a cache, and
caching a `BuildContext` handle itself is left to `no_stored_tree_context`.

```dart
// Rejected: _config never sees a new Config.
_config ??= context.watch<Config>();

// Accepted: read where it is used.
final config = context.watch<Config>();
```

## `watch_not_read_in_build`

Rejects `getInheritedValueOfExactType` and the provider `read` inside a
build. A dependency-free read does not register the element as a dependent,
so the build never reruns when the value changes. Use
`dependOnInheritedValueOfExactType` or `watch` in a build; the snapshot reads
belong in `initState`, callbacks and effects.

## `derive_dont_construct`

Rejects a constructor call — `new`, `const`, named, factory, a tear-off such
as `Posture.new`, or an explicit `super(...)` — of a class annotated
`@deriveOnly` (from `genesis_foundation`) from outside the library that
declares it. A value that composes down the tree is reached through `derive`
or `copyWith` on the ambient value, so a field set above is never silently
dropped:

```dart
@deriveOnly
final class Posture {
  const Posture._({required this.tier});

  final int tier;

  Posture copyWith({int? tier}) => Posture._(tier: tier ?? this.tier);
}
```

Parts of the declaring library may construct the class.

## `state_flag_threshold`

Rejects a `genesis_tree` `State` subclass that declares more than four
instance fields of type `bool` or `bool?`. Flags admit combinations no phase
allows; model the phases as a sealed state value and switch over it
exhaustively in `build`. Only fields the class itself declares are counted.

## `effects_only_in_leaves`

Rejects an invocation of a method or function annotated `@effect` (from
`genesis_foundation`), or of an override of one, from outside a class
annotated `@effectLeaf`. The mark is inherited, so annotating a base Element
covers its subclasses. Inside a leaf class the sanctioned call sites are its
lifecycle — `startOrAdopt`, `update`, `dispose` — and the helpers they call;
its build is not one of them. An `@effect` declaration may invoke other
effects, so effects compose.

```dart
@effectLeaf
abstract class ProcessElement extends Element {
  void startOrAdopt() => spawnProcess(command);
}
```
