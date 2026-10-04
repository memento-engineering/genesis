import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:genesis_lint/main.dart';
import 'package:test/test.dart';

void main() {
  test('entrypoint registers exactly the eight warnings', () {
    final registry = _RecordingPluginRegistry();

    expect(plugin, isA<LintExtension>());
    expect(plugin, isA<Plugin>());
    expect(plugin.name, 'genesis_lint');

    plugin.register(registry);

    expect(registry.lintRules, isEmpty);
    expect(
      registry.warningRules.map((rule) => rule.name),
      orderedEquals(const [
        'no_stored_tree_context',
        'use_tree_context_synchronously',
        'no_effects_in_build',
        'no_cached_dependency',
        'watch_not_read_in_build',
        'derive_dont_construct',
        'state_flag_threshold',
        'effects_only_in_leaves',
      ]),
    );
  });

  test('the six tree-shape rules report at warning severity', () {
    final registry = _RecordingPluginRegistry();
    plugin.register(registry);

    final treeShapeRules = registry.warningRules.skip(2).toList();
    expect(treeShapeRules, hasLength(6));
    for (final rule in treeShapeRules) {
      for (final code in rule.diagnosticCodes) {
        expect(
          code.severity,
          DiagnosticSeverity.WARNING,
          reason: '${code.lowerCaseName} must fail dart analyze',
        );
      }
    }
  });
}

final class _RecordingPluginRegistry implements PluginRegistry {
  final List<AbstractAnalysisRule> lintRules = [];
  final List<AbstractAnalysisRule> warningRules = [];

  @override
  void registerLintRule(AbstractAnalysisRule rule) => lintRules.add(rule);

  @override
  void registerWarningRule(AbstractAnalysisRule rule) => warningRules.add(rule);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
