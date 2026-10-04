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

Every rule is registered as a warning rule, so each is enabled without a
`diagnostics` mapping. The six tree-shape rules, from `no_effects_in_build`
on, report at warning severity, so `dart analyze` exits non-zero when one of
them fires; the two context rules report at info. None of them reports in a
package's `test/` directory.

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
`scheduleMicrotask`, `Stream.listen`, `setState`, `await`, and an assignment
or `++`/`--` that outlives the build — a field of `this`, a top-level or
static variable, or a property or index of any object the build did not make.
Constructing components and building local values stay legal: a write
through a local variable, or into a literal or constructor call, including
as a cascade (`<String, int>{}..['a'] = 1`), is local.

The rule checks what the build runs before it returns: its own body, a
closure invoked on the spot, a closure handed to a `dart:core` or
`dart:collection` method (`forEach`, `map`, `fold` and the rest) or to a
`generate` or `fromIterable` constructor, and a local function the build
calls or hands to such a method. A closure handed anywhere else — a
component's callback, an effect hook — runs later and is not checked.

The rule does not see through aliases or dynamic dispatch: a field written
through a local that aliases it, a closure stored in a variable and then
called, a callback run by a non-core helper such as `package:collection`'s
`forEachIndexed`, and a `Future` obtained from a getter are not reported.
Reading a `Future` is not starting one, and passing an existing `Future` to
a component is legal.

```dart
@override
Component build(BuildContext context) => switch (phase) {
  Idle() => const Waiting(),
  Running(:final command) => Spawn(command: command),
};
```

The process starts in `Spawn`'s Element, not in the build that emits it.

## `no_cached_dependency`

Rejects a `??=` into a field, a top-level variable, or a property of an
object the code did not just make, whose right-hand side calls a member on a `BuildContext` — `dependOnInheritedValueOfExactType`,
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
`genesis_foundation`), or of an override of one, from anywhere but a
sanctioned site. The sanctioned sites are an `@effect` declaration, so
effects compose, and, inside a class or mixin annotated `@effectLeaf`, its
lifecycle methods — `startOrAdopt`, `update` and `dispose` — and the methods,
getters and setters of the same class that a lifecycle method calls or tears
off, directly or through each other. These are the lifecycle names of the
effect-leaf Element contract an orchestrator declares on its own leaf base
class; `genesis_tree`'s `Element` does not declare `startOrAdopt`. The mark is
inherited, so annotating that base class covers its subclasses. A leaf's
constructor, field initializers, build and any member the lifecycle does not
reach are not sanctioned.

```dart
@effectLeaf
abstract class ProcessElement extends Element {
  void startOrAdopt() => _spawn();

  void _spawn() => spawnProcess(command);
}
```

Dispatch is resolved statically: a call through a supertype whose member is
not annotated is not reported, even when an override is.
