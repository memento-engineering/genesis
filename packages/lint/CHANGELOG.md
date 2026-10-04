## 0.3.0-dev.1

- Add six tree-shape rules that keep tree code declarative. They are enabled by default like the existing two and report at warning severity, so `dart analyze` fails on code that trips them:
  - `no_effects_in_build` rejects a `Future`- or `FutureOr`-returning invocation, a `Timer` construction or static call, `scheduleMicrotask`, `Stream.listen`, `setState`, `await`, and a write that outlives the call inside the build of a `Component` or `State`, including inside closures the build runs on the spot or hands to a core collection method.
  - `no_cached_dependency` rejects a `??=` into a field, top-level variable or non-local property whose right-hand side calls a member on a `BuildContext` or passes one as an argument.
  - `watch_not_read_in_build` rejects `getInheritedValueOfExactType` and `read` inside a build.
  - `derive_dont_construct` rejects constructing a `@deriveOnly` class outside the library that declares it.
  - `state_flag_threshold` rejects a `State` declaring more than four `bool` instance fields.
  - `effects_only_in_leaves` rejects invoking an `@effect` method or function anywhere but an `@effect` declaration or the `startOrAdopt`, `update` and `dispose` lifecycle of an `@effectLeaf` class and the members they reach.
- The annotations the new rules read ship in `genesis_foundation` 0.3.0-dev.2 and are matched by their declaring library, so a same-named annotation elsewhere is ignored.

## 0.2.0

- **Breaking:** rule implementation classes now use `BuildContext` terminology: migrate `NoStoredTreeContextRule` / `UseTreeContextSynchronouslyRule` to `NoStoredBuildContextRule` / `UseBuildContextSynchronouslyRule`. Deprecated aliases remain, while the shipped diagnostic codes `no_stored_tree_context` and `use_tree_context_synchronously` stay stable for analyzer configurations.

## 0.1.0

- Add `no_stored_tree_context` for unmanaged durable context storage.
- Add `use_tree_context_synchronously` for mounted checks after async gaps.
- Expose the extension through `package:genesis_lint/genesis_lint.dart` and widen the analyzer and analysis_server_plugin constraints to caret ranges.
