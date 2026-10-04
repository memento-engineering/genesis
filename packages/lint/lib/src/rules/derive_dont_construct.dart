import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../tree_types.dart';

/// Rejects constructing a `@deriveOnly` class outside its own library.
///
/// A value that composes down the tree is derived from the ambient value so
/// every field set above survives; constructing it bare elsewhere silently
/// drops whatever the ambient value carried.
class DeriveDontConstructRule extends AnalysisRule {
  /// The diagnostic reported for a bare construction.
  static const LintCode code = LintCode(
    'derive_dont_construct',
    "Do not construct the @deriveOnly class '{0}' outside its library.",
    correctionMessage:
        'Derive it from the ambient value with derive or copyWith.',
    uniqueName: 'LintCode.derive_dont_construct',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  DeriveDontConstructRule()
    : super(
        name: 'derive_dont_construct',
        description:
            'Rejects constructor calls of @deriveOnly classes from other '
            'libraries.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    final visitor = _ConstructionVisitor(this);
    registry
      ..addConstructorReference(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      ..addSuperConstructorInvocation(this, visitor);
  }
}

final class _ConstructionVisitor extends SimpleAstVisitor<void> {
  _ConstructionVisitor(this.rule);

  final DeriveDontConstructRule rule;

  @override
  void visitConstructorReference(ConstructorReference node) {
    _check(node, node.constructorName.element, node.constructorName);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node, node.constructorName.element, node.constructorName);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _check(node, node.element, node);
  }

  void _check(AstNode site, ConstructorElement? constructor, AstNode report) {
    final owner = constructor?.enclosingElement;
    if (owner == null || !hasFoundationAnnotation(owner, 'DeriveOnly')) return;

    final unit = site.thisOrAncestorOfType<CompilationUnit>();
    final library = unit?.declaredFragment?.element;
    if (library == null || library == owner.library) return;
    rule.reportAtNode(report, arguments: [owner.name ?? '']);
  }
}
