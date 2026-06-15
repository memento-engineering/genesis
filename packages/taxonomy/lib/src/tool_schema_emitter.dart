/// Projection 2: the LLM-facing JSON Schema.
///
/// Emits a `.g.json` JSON Schema (draft 2020-12) for authoring an A2UI
/// v0.9-shaped `updateComponents` message against the catalog: the type enum
/// via per-variant `component` const discriminators, prop types /
/// descriptions / defaults / required flags flowing through, `children`
/// present for containers only (and forbidden for leaves via
/// `additionalProperties: false`), and extension projections (e.g. `x-actions`)
/// applied per variant.
///
/// Deterministic: types sorted by name, props in catalog order, actions
/// sorted by name (extension-side), no timestamps.
library;

import 'dart:convert';

import 'catalog.dart';
import 'registry_emitter.dart';

/// Generates the tool-schema JSON for [catalog].
///
/// Provenance (`$comment`, title, description) is parameterized from the
/// catalog's name block. Each registered extension's
/// `augmentToolSchemaVariant` runs over every type variant — this is how
/// affordance declarations reach the LLM.
String emitToolSchema(Catalog catalog) {
  final schema = <String, Object?>{
    r'$comment': 'GENERATED — do not edit. ${dartProvenanceLine(catalog)}',
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'updateComponents (${catalog.name} catalog v${catalog.version})',
    'description':
        'A2UI v0.9-shaped updateComponents message for the ${catalog.name} '
        'catalog. Always emit the WHOLE component tree; the client '
        'reconciles by component id. Exactly one component must have id '
        '"root".',
    'type': 'object',
    'properties': {
      'version': {'const': 'v0.9'},
      'updateComponents': {
        'type': 'object',
        'properties': {
          'surfaceId': {
            'type': 'string',
            'description': 'Identifier of the surface being updated.',
          },
          'components': {
            'type': 'array',
            'description':
                'Flat adjacency list of components. Containers reference '
                'children by id.',
            'items': {
              'oneOf': [
                for (final type in catalog.types)
                  _componentVariant(catalog, type),
              ],
            },
          },
        },
        'required': ['surfaceId', 'components'],
        'additionalProperties': false,
      },
    },
    'required': ['version', 'updateComponents'],
    'additionalProperties': false,
  };
  return '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
}

Map<String, Object?> _componentVariant(Catalog catalog, CatalogType type) {
  final properties = <String, Object?>{
    'id': {
      'type': 'string',
      'description':
          'Unique, stable component id. Becomes the reconciliation key: '
          're-emit the same id to update a component in place.',
    },
    'component': {
      'const': type.name,
      'description': 'Component type discriminator.',
    },
    for (final prop in type.props) prop.name: _propSchema(prop),
    if (type.container)
      'children': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Ordered ids of child components. Every id must appear as a '
            'component in the same components list.',
      },
  };
  final variant = <String, Object?>{
    'type': 'object',
    'description': type.description,
    'properties': properties,
    'required': [
      'id',
      'component',
      for (final prop in type.props)
        if (prop.required) prop.name,
    ],
    'additionalProperties': false,
  };
  for (final extension in catalog.extensions) {
    extension.augmentToolSchemaVariant(type, variant);
  }
  return variant;
}

Map<String, Object?> _propSchema(CatalogProp prop) => {
  'type': prop.type == PropType.enumeration ? 'string' : prop.type.wireName,
  if (prop.type == PropType.enumeration) 'enum': prop.enumValues,
  'description': prop.description,
  if (!prop.required) 'default': prop.defaultValue,
};
