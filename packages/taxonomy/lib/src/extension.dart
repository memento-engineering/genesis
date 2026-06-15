/// The catalog extension seam.
///
/// The core catalog format owns only `description` / `container` / `props` /
/// `dart` at the type level. Any other type-level key must be claimed by a
/// registered [CatalogExtension] — otherwise parsing fails loudly with
/// `UnhandledCatalogKeysException`. Silent dropping (the failure mode where
/// `actions` would have vanished from the tool schema) is impossible by
/// construction.
///
/// [ActionsCatalogExtension] — the affordance channel — ships as the
/// proof of the seam: the `actions` block is itself extension vocabulary, not a
/// core key.
library;

import 'catalog.dart';
import 'errors.dart';

/// Handles catalog vocabulary the core format does not know.
///
/// A extension claims type-level keys via [typeKeys]; the parser routes each
/// claimed key's raw value through [parseTypeValue] and stores the result in
/// `CatalogType.extensions` under that key. At emit time,
/// [augmentToolSchemaVariant] lets the extension project its data into the
/// LLM-facing tool schema variant for each type.
abstract class CatalogExtension {
  /// Const-constructible so extension lists can be const.
  const CatalogExtension();

  /// Diagnostic name, surfaced in loud-key error messages.
  String get name;

  /// The type-level catalog keys this extension claims. Must not overlap the
  /// core keys or another registered extension's keys.
  Set<String> get typeKeys;

  /// Validates and parses the raw [value] of a claimed [key] on type
  /// [typeName]. Throws a `CatalogException` on malformed input; the
  /// returned object lands in `CatalogType.extensions[key]`.
  Object parseTypeValue({
    required String typeName,
    required String key,
    required Object? value,
  });

  /// Projects this extension's data into the tool-schema variant for [type].
  /// [variantSchema] is the mutable JSON-Schema object for the type's
  /// `oneOf` entry; the default implementation adds nothing.
  void augmentToolSchemaVariant(
    CatalogType type,
    Map<String, Object?> variantSchema,
  ) {}
}

/// One declared action affordance on a catalog type (the affordance
/// channel, carried as catalog data; `genesis_consent` consumes it later).
class ActionDeclaration {
  /// Creates a declaration of action [name] with its contract [description].
  const ActionDeclaration({required this.name, required this.description});

  /// Wire action name (the `name` field of an A2UI action message).
  final String name;

  /// Contract description: what the action does and what `context` payload
  /// it expects. Flows to the LLM through the tool schema.
  final String description;
}

/// Parses the `actions` type-level block and projects it into the tool
/// schema — structurally as `x-actions` and as prose in the variant
/// description.
final class ActionsCatalogExtension extends CatalogExtension {
  /// Creates the extension.
  const ActionsCatalogExtension();

  /// The type-level key this extension claims.
  static const String catalogKey = 'actions';

  @override
  String get name => 'actions';

  @override
  Set<String> get typeKeys => const {catalogKey};

  @override
  Object parseTypeValue({
    required String typeName,
    required String key,
    required Object? value,
  }) {
    final path = 'types/$typeName/$key';
    if (value is! Map || value.isEmpty) {
      throw CatalogFormatException(
        path: path,
        expected: 'a non-empty map of action name -> {"description": ...}',
        actual: value,
      );
    }
    final raw = value.cast<String, Object?>();
    final actionNames = raw.keys.toList()..sort();
    final actions = <String, ActionDeclaration>{};
    for (final actionName in actionNames) {
      final specRaw = raw[actionName];
      if (specRaw is! Map) {
        throw CatalogFormatException(
          path: '$path/$actionName',
          expected: 'an action object ({"description": ...})',
          actual: specRaw,
        );
      }
      final spec = specRaw.cast<String, Object?>();
      for (final specKey in spec.keys) {
        if (specKey != 'description' && specKey != r'$comment') {
          throw CatalogFormatException(
            path: '$path/$actionName/$specKey',
            expected: 'one of the known keys (\$comment, description)',
            actual: 'unknown key "$specKey"',
          );
        }
      }
      final description = spec['description'];
      if (description is! String || description.isEmpty) {
        throw CatalogFormatException(
          path: '$path/$actionName/description',
          expected: 'a non-empty string',
          actual: description,
        );
      }
      actions[actionName] = ActionDeclaration(
        name: actionName,
        description: description,
      );
    }
    return actions;
  }

  @override
  void augmentToolSchemaVariant(
    CatalogType type,
    Map<String, Object?> variantSchema,
  ) {
    final actions = type.actions;
    if (actions.isEmpty) return; // non-actionable types declare nothing
    // Structured affordance declaration (JSON Schema x- extension keyword).
    variantSchema['x-actions'] = {
      for (final a in actions.values) a.name: {'description': a.description},
    };
    // And prose, so an LLM reading only descriptions still discovers it.
    final affordances = actions.values
        .map((a) => '"${a.name}" — ${a.description}')
        .join(' ');
    variantSchema['description'] =
        '${variantSchema['description']} AFFORDS CLIENT ACTIONS: the client '
        'may send an A2UI action message with sourceComponentId set to this '
        "component's id and one of these action names: $affordances";
  }
}

/// The extensions registered when a caller does not supply its own list.
const List<CatalogExtension> defaultCatalogExtensions = [
  ActionsCatalogExtension(),
];
