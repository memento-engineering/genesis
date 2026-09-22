import 'dart:io';

final _root = File.fromUri(Platform.script).parent.parent;

const _retired = <String>{
  'Seed',
  'Branch',
  'TreeContext',
  'TreeOwner',
  'ComponentBranch',
  'StatelessSeed',
  'StatelessBranch',
  'StatefulSeed',
  'StatefulBranch',
  'InheritedSeed',
  'InheritedBranch',
  'InheritedModelSeed',
  'InheritedModelBranch',
  'SingleChildSeed',
  'SingleChildBranchMixin',
  'SingleChildStatelessSeed',
  'SingleChildStatelessBranch',
  'SingleChildStatefulSeed',
  'SingleChildStatefulBranch',
  'MultiChildSeed',
  'MultiChildBranch',
  'NestBranch',
  'Sprout',
  'SproutContext',
  'SproutBranch',
  'ProviderTreeContext',
  'RenderSeed',
  'RenderBranch',
  'StageBranch',
  'BoxBranch',
  'TextBranch',
  'SeedFactoryFn',
  'buildSeedTree',
  'createBranch',
  'branchId',
  'childBranch',
  'rootBranch',
  'runBranchBuild',
  'dependOnInheritedSeedOfExactType',
  'getInheritedSeedOfExactType',
};

const _compatibilityAllowlist = <String, Set<String>>{
  'packages/tree/lib/src/component.dart': {'Seed', 'createBranch'},
  'packages/tree/lib/src/element.dart': {
    'Seed',
    'Branch',
    'branchId',
    'dependOnInheritedSeedOfExactType',
    'getInheritedSeedOfExactType',
  },
  'packages/tree/lib/src/build_context.dart': {
    'TreeContext',
    'branchId',
    'dependOnInheritedSeedOfExactType',
    'getInheritedSeedOfExactType',
  },
  'packages/tree/lib/src/build_owner.dart': {'TreeOwner', 'runBranchBuild'},
  'packages/tree/lib/src/buildable_element.dart': {'ComponentBranch'},
  'packages/tree/lib/src/hook_component.dart': {
    'Sprout',
    'SproutContext',
    'SproutBranch',
    'createBranch',
    'branchId',
    'dependOnInheritedSeedOfExactType',
    'getInheritedSeedOfExactType',
  },
  'packages/tree/lib/src/stateless.dart': {
    'StatelessSeed',
    'StatelessBranch',
    'createBranch',
  },
  'packages/tree/lib/src/stateful.dart': {
    'StatefulSeed',
    'StatefulBranch',
    'createBranch',
  },
  'packages/tree/lib/src/inherited.dart': {
    'InheritedSeed',
    'InheritedBranch',
    'InheritedModelSeed',
    'InheritedModelBranch',
    'createBranch',
    'childBranch',
  },
  'packages/tree/lib/src/single_child.dart': {
    'SingleChildSeed',
    'SingleChildBranchMixin',
    'SingleChildStatelessSeed',
    'SingleChildStatelessBranch',
    'SingleChildStatefulSeed',
    'SingleChildStatefulBranch',
    'NestBranch',
    'createBranch',
  },
  'packages/tree/lib/src/multi_child.dart': {
    'MultiChildSeed',
    'MultiChildBranch',
    'createBranch',
  },
  'packages/tree/lib/src/seed.dart': {'Seed'},
  'packages/tree/lib/src/branch.dart': {'Branch'},
  'packages/tree/lib/src/tree_context.dart': {'TreeContext'},
  'packages/tree/lib/src/tree_owner.dart': {'TreeOwner'},
  'packages/tree/lib/src/component_branch.dart': {'ComponentBranch'},
  'packages/tree/lib/src/sprout.dart': {
    'Sprout',
    'SproutContext',
    'SproutBranch',
  },
  'packages/perception/lib/src/perception_context.dart': {
    'branchId',
    'dependOnInheritedSeedOfExactType',
    'getInheritedSeedOfExactType',
  },
  'packages/taxonomy/lib/src/component_tree_builder.dart': {'buildSeedTree'},
  'packages/taxonomy/lib/src/tree_builder.dart': {'buildSeedTree'},
  'packages/taxonomy/lib/src/registry_runtime.dart': {'SeedFactoryFn'},
  'packages/typesetting/lib/src/render_element.dart': {
    'RenderSeed',
    'RenderBranch',
    'Branch',
  },
  'packages/typesetting/lib/src/render_branch.dart': {
    'RenderSeed',
    'RenderBranch',
  },
  'packages/typesetting/lib/src/stage.dart': {'StageBranch'},
  'packages/typesetting/lib/src/box.dart': {'BoxBranch'},
  'packages/typesetting/lib/src/text.dart': {'TextBranch'},
  'packages/dialogue/lib/src/surface.dart': {'rootBranch'},
  'packages/consent/lib/src/router.dart': {'rootBranch'},
  'packages/lint/lib/src/build_context_type.dart': {'TreeContext', 'Branch'},
  'packages/lint/lib/src/tree_context_type.dart': const {},
  'packages/lint/lib/src/rules/no_stored_build_context.dart': {'TreeContext'},
  'packages/lint/lib/src/rules/use_build_context_synchronously.dart': {
    'TreeContext',
  },
  'packages/lint/lib/src/rules/no_stored_tree_context.dart': {'TreeContext'},
  'packages/lint/lib/src/rules/use_tree_context_synchronously.dart': {
    'TreeContext',
  },
};

void main() {
  final failures = <String>[];
  _checkResidualVocabulary(failures);
  _checkMigrationContract(failures);
  _checkReleaseMetadata(failures);

  if (failures.isNotEmpty) {
    stderr.writeln('Component vocabulary audit failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Component vocabulary audit passed.');
}

void _checkResidualVocabulary(List<String> failures) {
  final files = <File>[
    ..._packageLibraryFiles(),
    ..._dartFiles('apps/console/lib'),
    File('${_root.path}/README.md'),
    ..._markdownFiles('docs'),
    ...Directory('${_root.path}/packages')
        .listSync()
        .whereType<Directory>()
        .map((directory) => File('${directory.path}/README.md'))
        .where((file) => file.existsSync()),
  ];

  for (final file in files) {
    final relative = _relative(file);
    if (relative == 'docs/component-element-migration.md' ||
        relative.contains('/CHANGELOG.md') ||
        relative.startsWith('docs/decisions/') ||
        relative.startsWith('docs/evidence/')) {
      continue;
    }
    final allowed = _compatibilityAllowlist[relative] ?? const <String>{};
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      for (final identifier in _retired) {
        if (allowed.contains(identifier)) continue;
        if (RegExp(
          '\\b${RegExp.escape(identifier)}\\b',
        ).hasMatch(lines[index])) {
          failures.add('$relative:${index + 1} retains $identifier');
        }
      }
    }
  }
}

void _checkMigrationContract(List<String> failures) {
  final migration = File(
    '${_root.path}/docs/component-element-migration.md',
  ).readAsStringSync();
  const required = <String>[
    '`Seed` | `Component`',
    '`Branch` | `Element`',
    '`TreeContext` | `BuildContext`',
    '`TreeOwner` | `BuildOwner`',
    '`ComponentBranch` | `BuildableElement`',
    '`Sprout` / `SproutContext` / `SproutBranch`',
    '`RenderSeed` / `RenderBranch`',
    '`buildSeedTree` | `buildComponentTree`',
    '`seedType`',
    '`no_stored_tree_context`',
    'separately approved breaking release',
    'two-consumer rule',
    'dirtied during that scope is its descendant',
  ];
  for (final snippet in required) {
    if (!migration.contains(snippet)) {
      failures.add('migration concordance is missing $snippet');
    }
  }
}

void _checkReleaseMetadata(List<String> failures) {
  const versions = <String, String>{
    'foundation': '0.3.0',
    'tree': '0.5.0',
    'perception': '0.4.0',
    'taxonomy': '0.2.0',
    'typesetting': '0.2.0',
    'dialogue': '0.2.0',
    'consent': '0.2.0',
    'lint': '0.2.0',
  };
  for (final entry in versions.entries) {
    final pubspec = File(
      '${_root.path}/packages/${entry.key}/pubspec.yaml',
    ).readAsStringSync();
    if (!pubspec.contains('version: ${entry.value}')) {
      failures.add('${entry.key} is not version ${entry.value}');
    }
    if (pubspec.contains(RegExp(r'^\s+path:', multiLine: true))) {
      failures.add('${entry.key} contains a path dependency');
    }
    final changelog = File(
      '${_root.path}/packages/${entry.key}/CHANGELOG.md',
    ).readAsStringSync();
    if (!changelog.contains('## ${entry.value}\n\n- **Breaking:**')) {
      failures.add('${entry.key} changelog lacks a Breaking entry');
    }
  }

  const floors = <String, List<String>>{
    'packages/tree/pubspec.yaml': ['genesis_foundation: ^0.3.0'],
    'packages/perception/pubspec.yaml': [
      'genesis_foundation: ^0.3.0',
      'genesis_tree: ^0.5.0',
    ],
    'packages/taxonomy/pubspec.yaml': ['genesis_tree: ^0.5.0'],
    'packages/typesetting/pubspec.yaml': [
      'genesis_tree: ^0.5.0',
      'genesis_perception: ^0.4.0',
    ],
    'packages/dialogue/pubspec.yaml': [
      'genesis_taxonomy: ^0.2.0',
      'genesis_tree: ^0.5.0',
      'genesis_perception: ^0.4.0',
    ],
    'packages/consent/pubspec.yaml': [
      'genesis_dialogue: ^0.2.0',
      'genesis_taxonomy: ^0.2.0',
      'genesis_tree: ^0.5.0',
      'genesis_perception: ^0.4.0',
    ],
    'apps/console/pubspec.yaml': [
      'genesis_consent: ^0.2.0',
      'genesis_dialogue: ^0.2.0',
      'genesis_taxonomy: ^0.2.0',
      'genesis_tree: ^0.5.0',
      'genesis_typesetting: ^0.2.0',
    ],
  };
  for (final entry in floors.entries) {
    final contents = File('${_root.path}/${entry.key}').readAsStringSync();
    for (final floor in entry.value) {
      if (!contents.contains(floor)) {
        failures.add('${entry.key} is missing hosted floor $floor');
      }
    }
    if (contents.contains(RegExp(r'^\s+path:', multiLine: true))) {
      failures.add('${entry.key} contains a path dependency');
    }
  }

  final lintPubspec = File(
    '${_root.path}/packages/lint/pubspec.yaml',
  ).readAsStringSync();
  if (lintPubspec.contains('resolution: workspace')) {
    failures.add('packages/lint must remain outside workspace resolution');
  }
}

Iterable<File> _dartFiles(String relativeDirectory) =>
    Directory('${_root.path}/$relativeDirectory')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

Iterable<File> _packageLibraryFiles() => Directory('${_root.path}/packages')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) {
      final relative = _relative(file);
      return file.path.endsWith('.dart') && relative.contains('/lib/');
    });

Iterable<File> _markdownFiles(String relativeDirectory) =>
    Directory('${_root.path}/$relativeDirectory')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.md'));

String _relative(File file) => file.path.substring(_root.path.length + 1);
