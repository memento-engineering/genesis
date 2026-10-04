import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../tree_types.dart';

/// Rejects invoking an `@effect` member outside an `@effectLeaf` class.
///
/// An effect belongs to the leaf whose Element owns its artifact, so the
/// tree decides when it starts and stops. A call from anywhere else starts an
/// artifact nothing owns. Inside an `@effectLeaf` class the sanctioned sites
/// are its lifecycle methods — `startOrAdopt`, `update`, `dispose` — and the
/// members of the class they reach; a constructor, a field initializer, a
/// build and any other member are not. An `@effect` declaration may also
/// compose other effects.
class EffectsOnlyInLeavesRule extends AnalysisRule {
  /// The diagnostic reported for an effect invoked outside a leaf.
  static const LintCode code = LintCode(
    'effects_only_in_leaves',
    "Do not invoke the effect '{0}' outside an @effectLeaf class.",
    correctionMessage:
        'Move the call into the startOrAdopt, update or dispose of an '
        '@effectLeaf Element.',
    uniqueName: 'LintCode.effects_only_in_leaves',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  EffectsOnlyInLeavesRule()
    : super(
        name: 'effects_only_in_leaves',
        description:
            'Rejects @effect invocations outside an @effectLeaf class.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addMethodInvocation(this, _EffectCallVisitor(this));
  }
}

final class _EffectCallVisitor extends SimpleAstVisitor<void> {
  _EffectCallVisitor(this.rule);

  final EffectsOnlyInLeavesRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element is! ExecutableElement || !_isEffect(element.baseElement)) {
      return;
    }
    if (_isSanctionedSite(node)) return;
    rule.reportAtNode(node.methodName, arguments: [node.methodName.name]);
  }
}

/// Whether [element], or a member it overrides, is annotated `@effect`.
bool _isEffect(ExecutableElement element) {
  if (hasFoundationAnnotation(element, 'EffectMarker')) return true;
  final owner = element.enclosingElement;
  final name = element.name;
  if (element is! MethodElement || owner is! InterfaceElement || name == null) {
    return false;
  }
  return owner.allSupertypes.any((supertype) {
    final inherited = supertype.getMethod(name);
    return inherited != null &&
        hasFoundationAnnotation(inherited.baseElement, 'EffectMarker');
  });
}

/// The lifecycle methods of an effect leaf's Element.
const _lifecycleMethodNames = {'startOrAdopt', 'update', 'dispose'};

/// Whether the effect invoked at [node] runs from a sanctioned site: an
/// `@effect` declaration, or a lifecycle method of an `@effectLeaf` class or
/// a method of that class the lifecycle reaches.
bool _isSanctionedSite(AstNode node) {
  MethodDeclaration? member;
  for (AstNode? ancestor = node.parent; ancestor != null;) {
    switch (ancestor) {
      case FunctionDeclaration declaration:
        final function = declaration.declaredFragment?.element;
        if (function != null && _isEffect(function)) return true;
      case MethodDeclaration declaration:
        final method = declaration.declaredFragment?.element;
        if (method != null && _isEffect(method)) return true;
        member = declaration;
      case ConstructorDeclaration() || FieldDeclaration():
        return false;
      case ClassDeclaration declaration:
        return member != null &&
            _isEffectLeaf(declaration.declaredFragment?.element) &&
            _reachedFromLifecycle(declaration, member);
      case MixinDeclaration declaration:
        return member != null &&
            _isEffectLeaf(declaration.declaredFragment?.element) &&
            _reachedFromLifecycle(declaration, member);
      case CompilationUnit():
        return false;
    }
    ancestor = ancestor.parent;
  }
  return false;
}

/// Whether [member] of [container] is a lifecycle method, or a method,
/// getter or setter of [container] that a lifecycle method calls or tears
/// off, directly or through other such members. A build is never reached.
bool _reachedFromLifecycle(AstNode container, MethodDeclaration member) {
  final members = _MemberCollector();
  container.accept(members);
  final reached = <MethodDeclaration>{};
  final pending = [
    for (final declaration in members.declarations.values)
      if (_lifecycleMethodNames.contains(declaration.name.lexeme)) declaration,
  ];
  while (pending.isNotEmpty) {
    final declaration = pending.removeLast();
    if (buildMethodNames.contains(declaration.name.lexeme)) continue;
    if (!reached.add(declaration)) continue;
    final references = _ReferenceCollector();
    declaration.body.accept(references);
    for (final element in references.elements) {
      final callee = members.declarations[element];
      if (callee != null) pending.add(callee);
    }
  }
  return reached.contains(member);
}

/// Collects the methods, getters and setters a class or mixin declares.
final class _MemberCollector extends RecursiveAstVisitor<void> {
  final declarations = <Element, MethodDeclaration>{};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) declarations[element] = node;
  }
}

/// Collects the elements a body refers to by a simple name.
final class _ReferenceCollector extends RecursiveAstVisitor<void> {
  final elements = <Element>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null) elements.add(element.baseElement);
  }
}

/// Whether [element], or one of its supertypes, is annotated `@effectLeaf`.
bool _isEffectLeaf(InterfaceElement? element) {
  if (element == null) return false;
  return [
    element,
    ...element.allSupertypes.map((type) => type.element),
  ].any((candidate) => hasFoundationAnnotation(candidate, 'EffectLeafMarker'));
}
