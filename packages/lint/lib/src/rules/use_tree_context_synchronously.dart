import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../tree_context_type.dart';

/// Requires a same-handle `mounted` probe after an asynchronous gap.
class UseTreeContextSynchronouslyRule extends AnalysisRule {
  /// The diagnostic reported for an unguarded post-`await` use.
  static const LintCode code = LintCode(
    'use_tree_context_synchronously',
    'Do not use a TreeContext across an async gap without a mounted check.',
    correctionMessage: 'Check that this TreeContext is mounted after awaiting.',
    uniqueName: 'LintCode.use_tree_context_synchronously',
  );

  /// Creates the rule.
  UseTreeContextSynchronouslyRule()
    : super(
        name: 'use_tree_context_synchronously',
        description: 'Requires mounted checks after TreeContext async gaps.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addSimpleIdentifier(
      this,
      _UseTreeContextSynchronouslyVisitor(this),
    );
  }
}

final class _UseTreeContextSynchronouslyVisitor extends SimpleAstVisitor<void> {
  _UseTreeContextSynchronouslyVisitor(this.rule);

  final UseTreeContextSynchronouslyRule rule;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inGetterContext() || _isMountedProbe(node)) return;

    final element = node.element;
    final type = switch (element) {
      VariableElement variable => variable.type,
      ExecutableElement executable => executable.returnType,
      _ => node.staticType,
    };
    if (!isTreeContextType(type)) return;

    final baseElement = _canonicalElement(element);
    if (baseElement == null) return;
    if (_TreeContextAsyncStateTracker(node, baseElement).isUnsafe) {
      rule.reportAtNode(node);
    }
  }
}

final class _TreeContextAsyncStateTracker {
  _TreeContextAsyncStateTracker(this.use, this.baseElement);

  final SimpleIdentifier use;
  final Element baseElement;

  bool get isUnsafe {
    final functionBody = use.thisOrAncestorOfType<FunctionBody>();
    if (functionBody == null) return false;

    AstNode current = use;
    while (!identical(current, functionBody)) {
      final parent = current.parent;
      if (parent == null) return false;

      if (parent is Block) {
        final containingStatement = parent.statements.lastWhere(
          (statement) =>
              statement.offset <= current.offset &&
              statement.end >= current.end,
        );
        final index = parent.statements.indexOf(containingStatement);
        for (var i = index - 1; i >= 0; i--) {
          final statement = parent.statements[i];
          if (_isExitGuard(statement, baseElement)) return false;
          if (_containsAwait(statement)) return true;
        }
      } else if (parent is IfStatement &&
          _isInThenBranch(parent, current) &&
          _requiresMounted(parent.expression, baseElement)) {
        return false;
      }

      current = parent;
    }
    return false;
  }
}

bool _isInThenBranch(IfStatement statement, AstNode node) {
  final thenStatement = statement.thenStatement;
  return thenStatement.offset <= node.offset && thenStatement.end >= node.end;
}

bool _isExitGuard(Statement statement, Element baseElement) {
  if (statement is! IfStatement) return false;
  if (!_requiresUnmounted(statement.expression, baseElement)) return false;
  return _definitelyExits(statement.thenStatement);
}

bool _definitelyExits(Statement statement) {
  if (statement is ReturnStatement ||
      statement is BreakStatement ||
      statement is ContinueStatement) {
    return true;
  }
  if (statement is ExpressionStatement &&
      statement.expression is ThrowExpression) {
    return true;
  }
  if (statement is Block && statement.statements.isNotEmpty) {
    return _definitelyExits(statement.statements.last);
  }
  if (statement is IfStatement && statement.elseStatement != null) {
    return _definitelyExits(statement.thenStatement) &&
        _definitelyExits(statement.elseStatement!);
  }
  return false;
}

bool _requiresMounted(Expression expression, Element baseElement) {
  expression = _unparenthesized(expression);
  return _mountedBase(expression) == baseElement;
}

bool _requiresUnmounted(Expression expression, Element baseElement) {
  expression = _unparenthesized(expression);
  if (expression is PrefixExpression && expression.operator.lexeme == '!') {
    return _mountedBase(_unparenthesized(expression.operand)) == baseElement;
  }
  if (expression is! BinaryExpression) return false;

  final left = _unparenthesized(expression.leftOperand);
  final right = _unparenthesized(expression.rightOperand);
  final lexeme = expression.operator.lexeme;
  if (lexeme == '==') {
    return (_mountedBase(left) == baseElement && _isFalse(right)) ||
        (_isFalse(left) && _mountedBase(right) == baseElement);
  }
  if (lexeme == '!=') {
    return (_mountedBase(left) == baseElement && _isTrue(right)) ||
        (_isTrue(left) && _mountedBase(right) == baseElement);
  }
  return false;
}

Element? _mountedBase(Expression expression) {
  expression = _unparenthesized(expression);
  final target = switch (expression) {
    PrefixedIdentifier access when access.identifier.name == 'mounted' =>
      access.prefix,
    PropertyAccess access when access.propertyName.name == 'mounted' =>
      access.target,
    _ => null,
  };
  if (target == null || !isTreeContextType(target.staticType)) return null;
  return _canonicalElement(_contextElement(target));
}

Element? _contextElement(Expression expression) => switch (expression) {
  SimpleIdentifier identifier => identifier.element,
  PrefixedIdentifier identifier => identifier.identifier.element,
  PropertyAccess access => access.propertyName.element,
  MethodInvocation invocation => invocation.methodName.element,
  _ => null,
};

Element? _canonicalElement(Element? element) {
  if (element is PropertyAccessorElement && element.isOriginVariable) {
    return element.variable.baseElement;
  }
  return element?.baseElement;
}

bool _isMountedProbe(SimpleIdentifier node) {
  for (
    AstNode? ancestor = node.parent;
    ancestor != null && ancestor.offset <= node.offset;
    ancestor = ancestor.parent
  ) {
    final target = switch (ancestor) {
      PrefixedIdentifier access when access.identifier.name == 'mounted' =>
        access.prefix,
      PropertyAccess access when access.propertyName.name == 'mounted' =>
        access.target,
      _ => null,
    };
    if (target != null &&
        target.offset <= node.offset &&
        target.end >= node.end &&
        isTreeContextType(target.staticType)) {
      return true;
    }
    if (ancestor is Statement || ancestor is ArgumentList) return false;
  }
  return false;
}

Expression _unparenthesized(Expression expression) {
  while (expression is ParenthesizedExpression) {
    expression = expression.expression;
  }
  return expression;
}

bool _isFalse(Expression expression) =>
    expression is BooleanLiteral && !expression.value;

bool _isTrue(Expression expression) =>
    expression is BooleanLiteral && expression.value;

bool _containsAwait(AstNode node) {
  final visitor = _AwaitVisitor();
  node.accept(visitor);
  return visitor.found;
}

final class _AwaitVisitor extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    found = true;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}
