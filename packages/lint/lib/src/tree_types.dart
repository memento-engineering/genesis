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
/// variable, and a setter are durable. An index or property write is durable
/// unless its receiver is transient: a local variable, or a value created on
/// the spot (a collection or record literal, or a constructor call), reached
/// directly, through parentheses, or as the target of a cascade.
bool isDurableWrite(Expression target, Element? writeElement) =>
    switch (target) {
      IndexExpression(:final realTarget) ||
      PropertyAccess(:final realTarget) => !_isTransientReceiver(realTarget),
      PrefixedIdentifier(:final prefix) => !_isTransientReceiver(prefix),
      _ =>
        writeElement is! LocalVariableElement &&
            writeElement is! FormalParameterElement,
    };

bool _isTransientReceiver(Expression receiver) =>
    switch (receiver.unParenthesized) {
      SimpleIdentifier(:final element) => element is LocalVariableElement,
      TypedLiteral() || RecordLiteral() || InstanceCreationExpression() => true,
      CascadeExpression(:final target) => _isTransientReceiver(target),
      _ => false,
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
/// A closure is visited when it runs during the call: invoked on the spot, or
/// handed to a `dart:core` or `dart:collection` method such as `forEach`,
/// `map` or `fold`, or to a `generate` or `fromIterable` constructor. A local
/// function is visited when it is called, or handed to such a method, from
/// code that is itself visited. Any other closure or local function is handed
/// on to run later (a callback, an effect hook) and is not visited.
abstract class SynchronousBodyVisitor extends RecursiveAstVisitor<void> {
  final _localFunctions = <Element, FunctionExpression>{};
  final _visitedLocalFunctions = <Element>{};

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    final declaration = node.functionDeclaration;
    final element = declaration.declaredFragment?.element;
    if (element != null) {
      _localFunctions[element] = declaration.functionExpression;
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (isInvokedOnTheSpot(node) || isRunDuringTheCall(node)) {
      super.visitFunctionExpression(node);
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    final element = node.element;
    if (element == null) return;
    final function = _localFunctions[element];
    if (function == null) return;
    final parent = node.parent;
    final called = parent is MethodInvocation && parent.methodName == node;
    if (!called && !isRunDuringTheCall(node)) return;
    if (_visitedLocalFunctions.add(element)) function.body.accept(this);
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

/// Whether [argument] is a function the invoked member runs before it
/// returns.
///
/// The members of `dart:core` and `dart:collection` that take a function run
/// it synchronously — `forEach`, `map`, `where`, `fold`, `sort`,
/// `putIfAbsent` and the rest — as do the `generate` and `fromIterable`
/// constructors. Other constructors of those libraries may keep the function
/// for later (a `Finalizer` callback, a `SplayTreeMap` comparator), so they
/// do not count.
bool isRunDuringTheCall(Expression argument) {
  AstNode value = argument;
  var parent = value.parent;
  while (parent is ParenthesizedExpression || parent is NamedArgument) {
    value = parent!;
    parent = parent.parent;
  }
  if (parent is! ArgumentList) return false;
  final Element? callee = switch (parent.parent) {
    MethodInvocation(:final methodName) => methodName.element,
    InstanceCreationExpression(:final constructorName)
        when const {
          'generate',
          'fromIterable',
        }.contains(constructorName.name?.name) =>
      constructorName.element,
    _ => null,
  };
  final library = callee?.library?.uri.toString();
  return library == 'dart:core' || library == 'dart:collection';
}
