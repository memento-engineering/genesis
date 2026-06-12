/// Schema-first node vocabulary (ADR-0002): one catalog classifies the node
/// species; codegen emits the Dart factory registry and the LLM tool schema.
///
/// The programmatic core — `Catalog.parse`, `emitRegistry`, `emitToolSchema`,
/// `generateFromCatalog`, and the registry runtime — works without
/// build_runner; the builder in `package:genesis_taxonomy/builder.dart` is a
/// thin shell over it (ADR-0002 Decision 5).
library;

export 'src/catalog.dart';
export 'src/errors.dart';
export 'src/generate.dart';
export 'src/plugin.dart';
export 'src/registry_emitter.dart' show emitRegistry;
export 'src/registry_runtime.dart';
export 'src/tool_schema_emitter.dart' show emitToolSchema;
export 'src/tree_builder.dart';
