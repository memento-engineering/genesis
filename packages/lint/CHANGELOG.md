## 0.2.0

- **Breaking:** rule implementation classes now use `BuildContext` terminology: migrate `NoStoredTreeContextRule` / `UseTreeContextSynchronouslyRule` to `NoStoredBuildContextRule` / `UseBuildContextSynchronouslyRule`. Deprecated aliases remain, while the shipped diagnostic codes `no_stored_tree_context` and `use_tree_context_synchronously` stay stable for analyzer configurations.

## 0.1.0

- Add `no_stored_tree_context` for unmanaged durable context storage.
- Add `use_tree_context_synchronously` for mounted checks after async gaps.
- Expose the extension through `package:genesis_lint/genesis_lint.dart` and widen the analyzer and analysis_server_plugin constraints to caret ranges.
