import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

void main() {}

/// Shared analyzer fixture with a synthetic `genesis_tree` package.
abstract class TreeContextRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('genesis_tree').addFile('lib/genesis_tree.dart', r'''
abstract class TreeContext {
  bool get mounted;
  void markNeedsRebuild();
}

abstract class Branch {}
''');
    super.setUp();
  }
}
