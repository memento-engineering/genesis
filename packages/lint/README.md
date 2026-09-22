# genesis_lint

Static analysis rules that keep `BuildContext` capabilities scoped safely.
This package is an analyzer extension; applications do not import it at
runtime, and it deliberately has no dependency on `genesis_tree`. Rules match
the resolved declaring-library URI of the types they inspect.

Analyzer extensions are available on Dart 3.10 and later. Enable this one in
the top-level `plugins` section of a package-root or workspace-root
`analysis_options.yaml`:

```yaml
plugins:
  genesis_lint: ^0.2.0
```

For local development, replace the version with a path dependency:

```yaml
plugins:
  genesis_lint:
    path: packages/lint
```

Both diagnostics are warnings, so they are enabled without a `diagnostics`
mapping.

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
