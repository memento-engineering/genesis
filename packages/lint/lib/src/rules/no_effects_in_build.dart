import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../tree_types.dart';

/// Rejects effects inside the build method of a `Component` or `State`.
///
/// A build describes children and nothing else: it starts no asynchronous
/// work, schedules nothing, and writes no state that outlives the call.
/// Constructing components is the pure part of a build and is allowed.
class NoEffectsInBuildRule extends AnalysisRule {
  /// The diagnostic reported for an effect inside a build.
  static const LintCode code = LintCode(
    'no_effects_in_build',
    'Do not perform an effect inside build.',
    correctionMessage:
        'Emit a leaf Component whose Element owns the effect through '
        'startOrAdopt, update and dispose.',
    uniqueName: 'LintCode.no_effects_in_build',
  );

  /// Creates the rule.
  NoEffectsInBuildRule()
    : super(
        name: 'no_effects_in_build',
        description:
            'Rejects futures, timers, microtasks, setState and durable '
            'writes inside a build method.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addMethodDeclaration(this, _BuildMethodVisitor(this));
  }
}

final class _BuildMethodVisitor extends SimpleAstVisitor<void> {
  _BuildMethodVisitor(this.rule);

  final NoEffectsInBuildRule rule;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!isTreeBuildMethod(node)) return;
    node.body.accept(_EffectVisitor(rule));
  }
}

final class _EffectVisitor extends SynchronousBodyVisitor {
  _EffectVisitor(this.rule);

  final NoEffectsInBuildRule rule;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (isDurableWrite(node.leftHandSide, node.writeElement)) {
      rule.reportAtNode(node.leftHandSide);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    rule.reportAtNode(node);
    super.visitAwaitExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (isFutureType(node.staticType)) rule.reportAtNode(node);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    if (isDartAsyncMember(constructor, 'Timer') ||
        isFutureType(node.staticType)) {
      rule.reportAtNode(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isEffectInvocation(node)) rule.reportAtNode(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (_isIncrementOrDecrement(node.operator) &&
        isDurableWrite(node.operand, node.writeElement)) {
      rule.reportAtNode(node.operand);
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (_isIncrementOrDecrement(node.operator) &&
        isDurableWrite(node.operand, node.writeElement)) {
      rule.reportAtNode(node.operand);
    }
    super.visitPrefixExpression(node);
  }
}

bool _isEffectInvocation(MethodInvocation node) {
  if (isFutureType(node.staticType)) return true;

  final element = node.methodName.element;
  if (isDartAsyncMember(element, 'scheduleMicrotask')) return true;
  if (isDartAsyncMember(element, 'Timer')) return true;
  if (element is MethodElement && element.name == 'setState') {
    final owner = element.enclosingElement;
    return owner is InterfaceElement && isTreeSubtype(owner, 'State');
  }
  return false;
}

bool _isIncrementOrDecrement(Token operator) =>
    operator.type == TokenType.PLUS_PLUS ||
    operator.type == TokenType.MINUS_MINUS;
