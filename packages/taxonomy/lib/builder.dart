/// The build_runner shell over the programmatic generator core (ADR-0002
/// Decision 5).
///
/// Consumes a `*.catalog.json` asset and emits the `.g.dart` factory
/// registry plus the `.g.json` tool schema next to it (`build_to: source`,
/// so artifacts are committed and the generator-in-sync byte-equality check
/// is the standing CI guard). Everything substantive lives in
/// `generateFromCatalog`; this file only adapts it to the build API.
library;

import 'dart:async';

import 'package:build/build.dart';

import 'genesis_taxonomy.dart';

/// Entry point referenced by `build.yaml`.
Builder taxonomyBuilder(BuilderOptions options) => const TaxonomyBuilder();

/// Builds `<name>.g.dart` + `<name>.g.json` from `<name>.catalog.json`.
class TaxonomyBuilder implements Builder {
  /// Creates the builder.
  const TaxonomyBuilder();

  static const String _inputExtension = '.catalog.json';

  @override
  Map<String, List<String>> get buildExtensions => const {
    _inputExtension: ['.g.dart', '.g.json'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final catalogJson = await buildStep.readAsString(inputId);
    // The shipped builder runs with the default plugin set; domains needing
    // custom plugins wrap generateFromCatalog in their own builder.
    final outputs = generateFromCatalog(catalogJson);

    final basePath = inputId.path.substring(
      0,
      inputId.path.length - _inputExtension.length,
    );
    await buildStep.writeAsString(
      AssetId(inputId.package, '$basePath.g.dart'),
      outputs.registryDart,
    );
    await buildStep.writeAsString(
      AssetId(inputId.package, '$basePath.g.json'),
      outputs.toolSchemaJson,
    );
  }
}
