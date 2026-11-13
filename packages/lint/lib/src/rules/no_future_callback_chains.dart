import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../tree_types.dart';

/// The `Future` members that chain a callback onto a future.
const _chainMemberNames = {'then', 'catchError', 'whenComplete', 'onError'};

/// Rejects a callback chained onto a `Future`.
///
/// Asynchronous code is written with `async` and `await`: a call to `then`,
/// `catchError`, `whenComplete` or `onError` on a value whose static type is
/// a `Future` — or a subtype of one, a nullable one, a type variable bounded
/// by one, or a `FutureOr` narrowed to one — is reported at the member name.
/// A receiver the rule cannot type that way, such as a `dynamic` value, is
/// left alone. Unlike the tree rules, this rule also reports in a package's
/// `test/` directory.
class NoFutureCallbackChainsRule extends AnalysisRule {
  /// The diagnostic reported for a callback chained onto a `Future`.
  static const LintCode code = LintCode(
    'no_future_callback_chains',
    'Do not chain a callback onto a Future.',
    correctionMessage:
        'Await the future inside an async function and handle its failure '
        'with try/catch.',
    uniqueName: 'LintCode.no_future_callback_chains',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  NoFutureCallbackChainsRule()
    : super(
        name: 'no_future_callback_chains',
        description:
            'Rejects then, catchError, whenComplete and onError called on a '
            'Future; await the future inside try/catch instead.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _ChainVisitor(this));
  }
}

final class _ChainVisitor extends SimpleAstVisitor<void> {
  _ChainVisitor(this.rule);

  final NoFutureCallbackChainsRule rule;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_chainMemberNames.contains(node.methodName.name)) return;
    final receiver = node.realTarget;
    if (receiver == null) return;
    if (!isFutureType(_resolveBound(receiver.staticType))) return;
    rule.reportAtNode(node.methodName);
  }
}

/// Resolves [type] through type-variable bounds until it is not a type
/// variable.
DartType? _resolveBound(DartType? type) {
  var resolved = type;
  while (resolved is TypeParameterType) {
    resolved = resolved.bound;
  }
  return resolved;
}
