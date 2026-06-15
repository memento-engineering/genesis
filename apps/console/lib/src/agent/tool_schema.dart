import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Builds the flat `render` tool the agent offers the model.
///
/// Derived from the generated `console.g.json` so the tool stays in lockstep
/// with the catalog (single source). The model emits ONLY the `components`
/// array — the full A2UI envelope nesting breaks local models without
/// constrained decoding — and the console adds the version, surface id, and the
/// `screen` root.
Future<Map<String, Object?>> renderTool() async {
  final schema = jsonDecode(await _loadSchemaJson()) as Map<String, Object?>;
  final properties = schema['properties'] as Map<String, Object?>;
  final updateComponents =
      properties['updateComponents'] as Map<String, Object?>;
  final ucProps = updateComponents['properties'] as Map<String, Object?>;
  final componentsSchema = ucProps['components'] as Map<String, Object?>;
  return {
    'type': 'function',
    'function': {
      'name': 'render',
      'description':
          'Render or update the terminal screen by emitting the component tree '
          'as a flat array.',
      'parameters': {
        'type': 'object',
        'properties': {'components': componentsSchema},
        'required': ['components'],
      },
    },
  };
}

Future<String> _loadSchemaJson() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:genesis_console/console.g.json'),
  );
  if (uri == null) {
    throw StateError('cannot resolve package:genesis_console/console.g.json');
  }
  return File.fromUri(uri).readAsString();
}
