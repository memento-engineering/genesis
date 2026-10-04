import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The method names that describe a component's children.
///
/// `buildWithChild` is the build hook of the single-child composition
/// classes; it carries the same purity contract as `build`.
const buildMethodNames = {'build', 'buildWithChild'};

/// Whether [element] is declared in a `package:<packageName>/...` library.
bool isDeclaredInPackage(Element? element, String packageName) {
  final uri = element?.library?.uri;
  return uri != null &&
      uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == packageName;
}

/// Whether [element] is, or inherits from, the `genesis_tree` class [name].
///
/// The match is by the declaring library of the supertype, so a same-named
/// class from any other package is not a match.
bool isTreeSubtype(InterfaceElement? element, String name) {
  if (element == null) return false;
  return <InterfaceType>[element.thisType, ...element.allSupertypes].any(
    (type) =>
        type.element.name == name &&
        isDeclaredInPackage(type.element, 'genesis_tree'),
  );
}

/// Whether [node] is the build method of a `genesis_tree` `Component` or
/// `State` subclass.
bool isTreeBuildMethod(MethodDeclaration node) {
  if (node.isStatic || node.isGetter || node.isSetter) return false;
  if (!buildMethodNames.contains(node.name.lexeme)) return false;
  final owner = node.declaredFragment?.element.enclosingElement;
  if (owner is! InterfaceElement) return false;
  return isTreeSubtype(owner, 'Component') || isTreeSubtype(owner, 'State');
}

/// Whether [type] is `Future`, `FutureOr`, or a subtype of `Future`.
bool isFutureType(DartType? type) {
  if (type == null) return false;
  if (type.isDartAsyncFuture || type.isDartAsyncFutureOr) return true;
  if (type is! InterfaceType) return false;
  return type.allSupertypes.any((supertype) => supertype.isDartAsyncFuture);
}

/// Whether [element] is the `dart:async` declaration named [name], or a
/// member of the `dart:async` class [name].
bool isDartAsyncMember(Element? element, String name) {
  if (element == null) return false;
  if (element.library?.uri.toString() != 'dart:async') return false;
  if (element.name == name) return true;
  final owner = element.enclosingElement;
  return owner is InterfaceElement && owner.name == name;
}

/// Whether an assignment to [target], resolving to [writeElement], writes
/// state that outlives the enclosing function.
///
/// Locals and parameters are transient. A field, a top-level or static
/// variable, a setter, and a property of any object are durable. An index
/// write is durable unless it indexes a local variable.
bool isDurableWrite(Expression target, Element? writeElement) =>
    switch (target) {
      IndexExpression(:final realTarget) =>
        !(realTarget is SimpleIdentifier &&
            realTarget.element is LocalVariableElement),
      PropertyAccess() || PrefixedIdentifier() => true,
      _ =>
        writeElement is! LocalVariableElement &&
            writeElement is! FormalParameterElement,
    };

/// Whether [element] carries an annotation whose value is an instance of the
/// `genesis_foundation` class [className].
///
/// Both the constant form (`@deriveOnly`) and the constructor form
/// (`@DeriveOnly()`) match. A same-named annotation from any other package
/// does not.
bool hasFoundationAnnotation(Element element, String className) =>
    element.metadata.annotations.any((annotation) {
      final type = switch (annotation.element) {
        PropertyAccessorElement accessor => switch (accessor.variable.type) {
          InterfaceType type => type.element,
          _ => null,
        },
        ConstructorElement constructor => constructor.enclosingElement,
        _ => null,
      };
      return type != null &&
          type.name == className &&
          isDeclaredInPackage(type, 'genesis_foundation');
    });

/// Visits the code a build method runs synchronously.
///
/// A closure is skipped unless it is invoked on the spot, and a local
/// function declaration is skipped: both run later, outside the build, when
/// they are handed to a callback or an effect hook.
abstract class SynchronousBodyVisitor extends RecursiveAstVisitor<void> {
  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (isInvokedOnTheSpot(node)) super.visitFunctionExpression(node);
  }
}

/// Whether [function] is invoked where it is written, as in `(() {...})()`.
bool isInvokedOnTheSpot(FunctionExpression function) {
  AstNode value = function;
  var parent = value.parent;
  while (parent is ParenthesizedExpression) {
    value = parent;
    parent = parent.parent;
  }
  return parent is FunctionExpressionInvocation &&
      identical(parent.function, value);
}
