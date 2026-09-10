import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../tree_context_type.dart';

/// Rejects a `TreeContext` retained in unmanaged durable state.
class NoStoredTreeContextRule extends AnalysisRule {
  /// The diagnostic reported for a retained `TreeContext`.
  static const LintCode code = LintCode(
    'no_stored_tree_context',
    'Do not store a TreeContext in durable state.',
    correctionMessage: 'Use the TreeContext only in its synchronous scope.',
    uniqueName: 'LintCode.no_stored_tree_context',
  );

  /// Creates the rule.
  NoStoredTreeContextRule()
    : super(
        name: 'no_stored_tree_context',
        description: 'Rejects TreeContext capabilities retained in state.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;

    final visitor = _NoStoredTreeContextVisitor(this);
    registry
      ..addAssignmentExpression(this, visitor)
      ..addConstructorFieldInitializer(this, visitor)
      ..addFieldFormalParameter(this, visitor)
      ..addFunctionExpression(this, visitor)
      ..addListLiteral(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addSetOrMapLiteral(this, visitor)
      ..addVariableDeclaration(this, visitor);
  }
}

final class _NoStoredTreeContextVisitor extends SimpleAstVisitor<void> {
  _NoStoredTreeContextVisitor(this.rule);

  final NoStoredTreeContextRule rule;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_isManagedOwner(node)) return;
    if (!_isDurableAssignmentTarget(node.leftHandSide)) return;

    final value = node.rightHandSide;
    if (isTreeContextType(value.staticType)) rule.reportAtNode(value);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    if (_isManagedOwner(node)) return;

    final value = node.expression;
    if (isTreeContextType(value.staticType)) rule.reportAtNode(value);
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    if (_isManagedOwner(node)) return;
    if (isTreeContextType(node.declaredFragment?.element.type)) {
      rule.reportAtToken(node.name);
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (_isManagedOwner(node) || !_escapes(node)) return;

    node.body.accept(_CapturedContextVisitor(rule, node.offset));
  }

  @override
  void visitListLiteral(ListLiteral node) {
    if (_isManagedOwner(node)) return;
    _reportCollectionElements(node.elements);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isManagedOwner(node)) return;

    final storedArguments = _storedCollectionArguments(node);
    for (final argument in storedArguments) {
      final storesIterable =
          node.methodName.name == 'addAll' ||
          node.methodName.name == 'insertAll';
      if (storesIterable
          ? _isIterableOfTreeContext(argument.staticType)
          : isTreeContextType(argument.staticType)) {
        rule.reportAtNode(argument);
      }
    }
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    if (_isManagedOwner(node)) return;
    _reportCollectionElements(node.elements);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_isManagedOwner(node) || !_isDurableVariable(node)) return;

    final value = node.initializer;
    if (value != null && isTreeContextType(value.staticType)) {
      rule.reportAtNode(value);
    }
  }

  void _reportCollectionElements(NodeList<CollectionElement> elements) {
    for (final element in elements) {
      _reportCollectionElement(element);
    }
  }

  void _reportCollectionElement(CollectionElement element) {
    switch (element) {
      case Expression expression:
        if (isTreeContextType(expression.staticType)) {
          rule.reportAtNode(expression);
        }
      case MapLiteralEntry entry:
        if (isTreeContextType(entry.key.staticType)) {
          rule.reportAtNode(entry.key);
        }
        if (isTreeContextType(entry.value.staticType)) {
          rule.reportAtNode(entry.value);
        }
      case SpreadElement spread:
        if (_isIterableOfTreeContext(spread.expression.staticType)) {
          rule.reportAtNode(spread.expression);
        }
      case IfElement conditional:
        _reportCollectionElement(conditional.thenElement);
        final elseElement = conditional.elseElement;
        if (elseElement != null) _reportCollectionElement(elseElement);
      case ForElement loop:
        _reportCollectionElement(loop.body);
      case NullAwareElement nullAware:
        if (isTreeContextType(nullAware.value.staticType)) {
          rule.reportAtNode(nullAware.value);
        }
      default:
    }
  }

  bool _escapes(FunctionExpression function) {
    AstNode value = function;
    AstNode? parent = value.parent;
    unwrap:
    while (true) {
      switch (parent) {
        case ParenthesizedExpression wrapper:
          value = wrapper;
          parent = wrapper.parent;
        case AsExpression wrapper:
          value = wrapper;
          parent = wrapper.parent;
        default:
          break unwrap;
      }
    }

    if (parent is FunctionExpressionInvocation &&
        identical(parent.function, value)) {
      return false;
    }
    if (parent is ReturnStatement || parent is ExpressionFunctionBody) {
      return true;
    }
    if (parent is AssignmentExpression &&
        identical(parent.rightHandSide, value)) {
      return _isDurableAssignmentTarget(parent.leftHandSide);
    }
    if (parent is VariableDeclaration && identical(parent.initializer, value)) {
      return _isDurableVariable(parent);
    }
    if (parent is ConstructorFieldInitializer) return true;
    if (parent is ListLiteral || parent is SetOrMapLiteral) return true;

    final argumentList = parent?.thisOrAncestorOfType<ArgumentList>();
    final invocation = argumentList?.parent;
    if (argumentList != null && invocation is MethodInvocation) {
      final arguments = argumentList.arguments;
      final argumentIndex = arguments.indexWhere(
        (argument) =>
            argument.offset <= function.offset && argument.end >= function.end,
      );
      return _storedCollectionArgumentIndexes(
        invocation,
      ).contains(argumentIndex);
    }
    return false;
  }
}

final class _CapturedContextVisitor extends RecursiveAstVisitor<void> {
  _CapturedContextVisitor(this.rule, this.closureOffset);

  final NoStoredTreeContextRule rule;
  final int closureOffset;

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inGetterContext()) return;
    final element = node.element;
    if (element is! LocalVariableElement &&
        element is! FormalParameterElement) {
      return;
    }
    final variable = element as VariableElement;
    if (variable.firstFragment.offset >= closureOffset) return;
    if (isTreeContextType(variable.type)) rule.reportAtNode(node);
  }
}

bool _isDurableVariable(VariableDeclaration node) {
  final declarationList = node.parent;
  final owner = declarationList?.parent;
  return owner is FieldDeclaration || owner is TopLevelVariableDeclaration;
}

bool _isDurableAssignmentTarget(Expression target) {
  if (target is IndexExpression) return true;

  final parent = target.parent;
  final element =
      parent is AssignmentExpression && identical(parent.leftHandSide, target)
      ? parent.writeElement
      : switch (target) {
          SimpleIdentifier identifier => identifier.element,
          PrefixedIdentifier identifier => identifier.identifier.element,
          PropertyAccess access => access.propertyName.element,
          _ => null,
        };
  return switch (element) {
    FieldElement() || TopLevelVariableElement() => true,
    PropertyAccessorElement accessor =>
      accessor.variable is FieldElement ||
          accessor.variable is TopLevelVariableElement ||
          accessor is SetterElement,
    _ => false,
  };
}

Iterable<Expression> _storedCollectionArguments(MethodInvocation node) sync* {
  final indexes = _storedCollectionArgumentIndexes(node);
  final arguments = node.argumentList.arguments;
  for (final index in indexes) {
    if (index < arguments.length) yield arguments[index].argumentExpression;
  }
}

Set<int> _storedCollectionArgumentIndexes(MethodInvocation node) {
  if (!_isListOrSetInvocation(node)) return const {};
  return switch (node.methodName.name) {
    'add' || 'addAll' => const {0},
    'insert' || 'insertAll' when _isListInvocation(node) => const {1},
    _ => const {},
  };
}

bool _isListOrSetInvocation(MethodInvocation node) {
  final receiver = node.realTarget?.staticType;
  if (_isCoreInterface(receiver, const {'List', 'Set'})) return true;

  final element = node.methodName.element;
  return element is MethodElement &&
      element.enclosingElement is InterfaceElement &&
      _isCoreInterface(
        (element.enclosingElement as InterfaceElement).thisType,
        const {'List', 'Set'},
      );
}

bool _isListInvocation(MethodInvocation node) {
  final receiver = node.realTarget?.staticType;
  if (_isCoreInterface(receiver, const {'List'})) return true;

  final element = node.methodName.element;
  return element is MethodElement &&
      element.enclosingElement is InterfaceElement &&
      _isCoreInterface(
        (element.enclosingElement as InterfaceElement).thisType,
        const {'List'},
      );
}

bool _isIterableOfTreeContext(DartType? type) {
  final erasedType = type?.extensionTypeErasure;
  if (erasedType is! InterfaceType) return false;
  for (final candidate in <InterfaceType>[
    erasedType,
    ...erasedType.allSupertypes,
  ]) {
    if (candidate.element.name == 'Iterable' &&
        candidate.element.library.uri.toString() == 'dart:core' &&
        candidate.typeArguments.isNotEmpty &&
        isTreeContextType(candidate.typeArguments.first)) {
      return true;
    }
  }
  return false;
}

bool _isCoreInterface(DartType? type, Set<String> names) {
  final erasedType = type?.extensionTypeErasure;
  if (erasedType is! InterfaceType) return false;
  return <InterfaceType>[erasedType, ...erasedType.allSupertypes].any(
    (type) =>
        names.contains(type.element.name) &&
        type.element.library.uri.toString() == 'dart:core',
  );
}

bool _isManagedOwner(AstNode node) {
  for (AstNode? ancestor = node; ancestor != null; ancestor = ancestor.parent) {
    final type = switch (ancestor) {
      ClassDeclaration declaration =>
        declaration.declaredFragment?.element.thisType,
      EnumDeclaration declaration =>
        declaration.declaredFragment?.element.thisType,
      ExtensionTypeDeclaration declaration =>
        declaration.declaredFragment?.element.thisType,
      MixinDeclaration declaration =>
        declaration.declaredFragment?.element.thisType,
      _ => null,
    };
    if (type != null) return isTreeManagedType(type);
  }
  return false;
}
