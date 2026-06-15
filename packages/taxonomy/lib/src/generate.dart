/// The programmatic generator core.
///
/// Pure (String in, Strings out) so the same code path is exercised by the
/// build_runner builder (writes files) and by generator-in-sync tests
/// (compare in-memory output to the files on disk, proving determinism and
/// provenance). The builder in `package:genesis_taxonomy/builder.dart` is a
/// thin shell over this function; everything here works without
/// build_runner.
library;

import 'catalog.dart';
import 'extension.dart';
import 'registry_emitter.dart';
import 'tool_schema_emitter.dart';

/// The two projections generated from one catalog.
class GeneratedOutputs {
  /// Bundles the projections.
  const GeneratedOutputs({
    required this.registryDart,
    required this.toolSchemaJson,
  });

  /// Contents of the generated `.g.dart` factory registry.
  final String registryDart;

  /// Contents of the generated `.g.json` LLM tool schema.
  final String toolSchemaJson;
}

/// Parses [catalogJson] and emits both projections.
///
/// Throws structured `CatalogException`s on malformed catalogs — including
/// the loud-extension-key failure when a type-level key is claimed by no extension
/// in [extensions]. Byte-deterministic: two runs over the same input are
/// identical.
GeneratedOutputs generateFromCatalog(
  String catalogJson, {
  List<CatalogExtension> extensions = defaultCatalogExtensions,
}) {
  final catalog = Catalog.parse(catalogJson, extensions: extensions);
  return GeneratedOutputs(
    registryDart: emitRegistry(catalog),
    toolSchemaJson: emitToolSchema(catalog),
  );
}
