import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

void main() {}

/// Shared analyzer fixture with a synthetic `genesis_tree` package.
abstract class BuildContextRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('genesis_tree').addFile('lib/genesis_tree.dart', r'''
abstract class BuildContext {
  bool get mounted;
  void markNeedsRebuild();
}

typedef TreeContext = BuildContext;

abstract class Element {}

typedef Branch = Element;
''');
    super.setUp();
  }
}
