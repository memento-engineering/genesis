import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../build_context_type.dart';
import '../tree_types.dart';

/// Rejects a `??=` cache of a value read through a `BuildContext`.
///
/// A dependency read from the tree must be read again on every build so a
/// change to the provided value propagates. Caching it in durable state with
/// `??=` freezes the first value it saw. Caching a `BuildContext` handle
/// itself is not a dependency read; retaining one is governed by
/// `no_stored_tree_context`.
class NoCachedDependencyRule extends AnalysisRule {
  /// The diagnostic reported for a cached tree dependency.
  static const LintCode code = LintCode(
    'no_cached_dependency',
    'Do not cache a value read through a BuildContext with ??=.',
    correctionMessage:
        'Read the dependency with dependOnInheritedValueOfExactType or watch '
        'where it is used.',
    uniqueName: 'LintCode.no_cached_dependency',
  );

  /// Creates the rule.
  NoCachedDependencyRule()
    : super(
        name: 'no_cached_dependency',
        description: 'Rejects ??= caches of BuildContext reads.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addAssignmentExpression(this, _CachedDependencyVisitor(this));
  }
}

final class _CachedDependencyVisitor extends SimpleAstVisitor<void> {
  _CachedDependencyVisitor(this.rule);

  final NoCachedDependencyRule rule;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.operator.type != TokenType.QUESTION_QUESTION_EQ) return;
    if (!isDurableWrite(node.leftHandSide, node.writeElement)) return;
    if (isBuildContextType(node.rightHandSide.staticType)) return;

    final finder = _ContextReadFinder();
    node.rightHandSide.accept(finder);
    if (finder.found) rule.reportAtNode(node);
  }
}

/// Finds a read through a `BuildContext` among the expressions evaluated now.
final class _ContextReadFinder extends SynchronousBodyVisitor {
  bool found = false;

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_takesBuildContext(node.argumentList)) found = true;
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_takesBuildContext(node.argumentList)) found = true;
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isBuildContextType(node.realTarget?.staticType) ||
        _takesBuildContext(node.argumentList)) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }
}

bool _takesBuildContext(ArgumentList arguments) => arguments.arguments.any(
  (argument) => isBuildContextType(argument.argumentExpression.staticType),
);
