import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/no_stored_build_context.dart';
import 'src/rules/use_build_context_synchronously.dart';

/// The analysis-server entrypoint for the genesis lint extension.
final plugin = LintExtension();

/// Registers the genesis build-context analysis warnings.
class LintExtension extends Plugin {
  /// The extension name reported to the analysis server.
  @override
  String get name => 'genesis_lint';

  /// Registers all warnings vended by this extension.
  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(NoStoredBuildContextRule())
      ..registerWarningRule(UseBuildContextSynchronouslyRule());
  }
}
