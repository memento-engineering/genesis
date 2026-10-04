import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../build_context_type.dart';
import '../tree_types.dart';

/// Rejects a dependency-free inherited lookup inside a build method.
///
/// A build that reads an inherited value without depending on it is not
/// rebuilt when the value changes, so its children describe a stale
/// configuration.
class WatchNotReadInBuildRule extends AnalysisRule {
  /// The diagnostic reported for a snapshot read inside a build.
  static const LintCode code = LintCode(
    'watch_not_read_in_build',
    'Do not read an inherited value without depending on it inside build.',
    correctionMessage:
        'Use dependOnInheritedValueOfExactType or watch so the build reruns '
        'when the value changes.',
    uniqueName: 'LintCode.watch_not_read_in_build',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  WatchNotReadInBuildRule()
    : super(
        name: 'watch_not_read_in_build',
        description:
            'Rejects getInheritedValueOfExactType and read inside a build '
            'method.',
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

  final WatchNotReadInBuildRule rule;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!isTreeBuildMethod(node)) return;
    node.body.accept(_SnapshotReadVisitor(rule));
  }
}

final class _SnapshotReadVisitor extends SynchronousBodyVisitor {
  _SnapshotReadVisitor(this.rule);

  final WatchNotReadInBuildRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isSnapshotRead(node)) rule.reportAtNode(node.methodName);
    super.visitMethodInvocation(node);
  }
}

bool _isSnapshotRead(MethodInvocation node) {
  final name = node.methodName.name;
  final element = node.methodName.element;
  if (name.startsWith('getInherited')) {
    return isBuildContextType(node.realTarget?.staticType);
  }
  if (name == 'read') {
    return element?.enclosingElement is ExtensionElement &&
        isDeclaredInPackage(element, 'genesis_tree');
  }
  return false;
}
