import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:genesis_lint/main.dart';
import 'package:test/test.dart';

void main() {
  test('entrypoint registers exactly the two warnings', () {
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
      ]),
    );
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
