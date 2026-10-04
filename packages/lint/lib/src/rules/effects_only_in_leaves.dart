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
/// members they reach, across the leaf's hierarchy as declared in one file;
/// a constructor, a field initializer, a build and any other member are not.
/// An `@effect` declaration may also compose other effects.
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
      case ClassDeclaration() || MixinDeclaration():
        final container = switch (ancestor) {
          ClassDeclaration(:final declaredFragment) =>
            declaredFragment?.element,
          MixinDeclaration(:final declaredFragment) =>
            declaredFragment?.element,
          _ => null,
        };
        return member != null &&
            container != null &&
            _isEffectLeaf(container) &&
            _reachedFromLifecycle(container, member);
      case CompilationUnit():
        return false;
    }
    ancestor = ancestor.parent;
  }
  return false;
}

/// Whether [member] of [container] is reached from a lifecycle method of an
/// instance of [container] or of one of its subtypes.
///
/// The hierarchy is read from the file that declares [container]: for that
/// class or mixin and every class or mixin of the file that extends,
/// implements or mixes it in, the members of the type and of its supertypes
/// declared in the same file are walked together, from every lifecycle
/// method among them. A reference to a member by name reaches every member
/// of that name and kind in the walked hierarchy, so an override and the
/// declaration it overrides are reached together. A build is never reached.
bool _reachedFromLifecycle(
  InterfaceElement container,
  MethodDeclaration member,
) {
  final unit = member.thisOrAncestorOfType<CompilationUnit>();
  if (unit == null) return false;
  final declarations = <InterfaceElement, List<MethodDeclaration>>{};
  for (final declaration in unit.declarations) {
    final (element, members) = switch (declaration) {
      ClassDeclaration(:final declaredFragment) => (
        declaredFragment?.element,
        declaration.body.members,
      ),
      MixinDeclaration(:final declaredFragment) => (
        declaredFragment?.element,
        declaration.body.members,
      ),
      _ => (null, const <ClassMember>[]),
    };
    if (element == null) continue;
    declarations[element] = members.whereType<MethodDeclaration>().toList();
  }
  for (final type in declarations.keys) {
    if (!_isSubtypeOf(type, container) || !_isEffectLeaf(type)) continue;
    final hierarchy = [
      for (final candidate in [
        type,
        ...type.allSupertypes.map((supertype) => supertype.element),
      ])
        ...?declarations[candidate],
    ];
    if (_reachedIn(hierarchy).contains(member)) return true;
  }
  return false;
}

bool _isSubtypeOf(InterfaceElement type, InterfaceElement container) =>
    type == container ||
    type.allSupertypes.any((supertype) => supertype.element == container);

/// The members of [hierarchy] a lifecycle method reaches by calling, tearing
/// off, reading or assigning them, directly or through each other.
Set<MethodDeclaration> _reachedIn(List<MethodDeclaration> hierarchy) {
  final byKey = <_MemberKey, List<MethodDeclaration>>{};
  for (final declaration in hierarchy) {
    final key = _keyOfDeclaration(declaration);
    (byKey[key] ??= []).add(declaration);
  }
  final reached = <MethodDeclaration>{};
  final pending = [
    for (final declaration in hierarchy)
      if (!declaration.isGetter &&
          !declaration.isSetter &&
          _lifecycleMethodNames.contains(declaration.name.lexeme))
        declaration,
  ];
  while (pending.isNotEmpty) {
    final declaration = pending.removeLast();
    if (buildMethodNames.contains(declaration.name.lexeme)) continue;
    if (!reached.add(declaration)) continue;
    final references = _ReferenceCollector();
    declaration.body.accept(references);
    for (final element in references.elements) {
      final key = _keyOfElement(element);
      if (key != null) pending.addAll(byKey[key] ?? const []);
    }
  }
  return reached;
}

/// The name and kind — method, getter or setter — of a member.
typedef _MemberKey = ({String name, int kind});

_MemberKey _keyOfDeclaration(MethodDeclaration declaration) => (
  name: declaration.name.lexeme,
  kind: declaration.isGetter
      ? 1
      : declaration.isSetter
      ? 2
      : 0,
);

_MemberKey? _keyOfElement(Element element) {
  final name = element.name;
  if (name == null || element.enclosingElement is! InterfaceElement) {
    return null;
  }
  return switch (element) {
    GetterElement() => (name: name, kind: 1),
    SetterElement() => (name: name, kind: 2),
    MethodElement() => (name: name, kind: 0),
    _ => null,
  };
}

/// Collects the members a body refers to: by a simple name, and the getter
/// and setter an assignment, `++` or `--` reads and writes.
final class _ReferenceCollector extends RecursiveAstVisitor<void> {
  final elements = <Element>{};

  void _add(Element? element) {
    if (element != null) elements.add(element.baseElement);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => _add(node.element);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _add(node.readElement);
    _add(node.writeElement);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _add(node.readElement);
    _add(node.writeElement);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _add(node.readElement);
    _add(node.writeElement);
    super.visitPrefixExpression(node);
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
