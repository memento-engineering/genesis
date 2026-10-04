import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/derive_dont_construct.dart';
import 'src/rules/effects_only_in_leaves.dart';
import 'src/rules/no_cached_dependency.dart';
import 'src/rules/no_effects_in_build.dart';
import 'src/rules/no_stored_build_context.dart';
import 'src/rules/state_flag_threshold.dart';
import 'src/rules/use_build_context_synchronously.dart';
import 'src/rules/watch_not_read_in_build.dart';

/// The analysis-server entrypoint for the genesis lint extension.
final plugin = LintExtension();

/// Registers the genesis build-context and tree-shape analysis warnings.
class LintExtension extends Plugin {
  /// The extension name reported to the analysis server.
  @override
  String get name => 'genesis_lint';

  /// Registers all warnings vended by this extension.
  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(NoStoredBuildContextRule())
      ..registerWarningRule(UseBuildContextSynchronouslyRule())
      ..registerWarningRule(NoEffectsInBuildRule())
      ..registerWarningRule(NoCachedDependencyRule())
      ..registerWarningRule(WatchNotReadInBuildRule())
      ..registerWarningRule(DeriveDontConstructRule())
      ..registerWarningRule(StateFlagThresholdRule())
      ..registerWarningRule(EffectsOnlyInLeavesRule());
  }
}
