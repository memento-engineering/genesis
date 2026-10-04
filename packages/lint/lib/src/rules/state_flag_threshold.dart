import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../tree_types.dart';

/// The most `bool` instance fields a `State` may declare.
const stateFlagThreshold = 4;

/// Rejects a `State` that tracks its phase in a handful of boolean flags.
///
/// Flags admit combinations no phase allows. A sealed state value makes each
/// phase one case, and an exhaustive switch in build emits its children.
class StateFlagThresholdRule extends AnalysisRule {
  /// The diagnostic reported for a flag-heavy `State`.
  static const LintCode code = LintCode(
    'state_flag_threshold',
    "The State '{0}' declares {1} bool fields; at most "
        '$stateFlagThreshold are allowed.',
    correctionMessage:
        'Model the phases as a sealed state value and switch over it in '
        'build.',
    uniqueName: 'LintCode.state_flag_threshold',
  );

  /// Creates the rule.
  StateFlagThresholdRule()
    : super(
        name: 'state_flag_threshold',
        description:
            'Rejects a State declaring more than $stateFlagThreshold bool '
            'instance fields.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addClassDeclaration(this, _StateClassVisitor(this));
  }
}

final class _StateClassVisitor extends SimpleAstVisitor<void> {
  _StateClassVisitor(this.rule);

  final StateFlagThresholdRule rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (!isTreeSubtype(element, 'State')) return;

    var flags = 0;
    for (final member in node.body.members) {
      if (member is! FieldDeclaration || member.isStatic) continue;
      for (final variable in member.fields.variables) {
        final type = variable.declaredFragment?.element.type;
        if (type != null && type.isDartCoreBool) flags++;
      }
    }
    if (flags > stateFlagThreshold) {
      rule.reportAtToken(
        node.namePart.typeName,
        arguments: [node.namePart.typeName.lexeme, flags],
      );
    }
  }
}
