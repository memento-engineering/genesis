// The genesis register's CI check.
//
// Runs the same `DecisionLintService` the station composes behind
// `lunar decisions lint`. genesis's docs/decisions declares no `roster:`
// surfaces, so unlike the org register (memento-engineering/tool) there is no
// exemption to partition out: every diagnostic is fatal.
//
// Usage: dart run lint_register.dart [repoRoot]   (default: the parent of cwd)
import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final repoRoot = p.normalize(
    p.absolute(arguments.isEmpty ? '..' : arguments.single),
  );
  final registerPath = p.join(repoRoot, 'docs', 'decisions');

  if (!Directory(registerPath).existsSync()) {
    stderr.writeln('no register at $registerPath');
    exitCode = 2;
    return;
  }

  final result = const DecisionLintService().lint(
    registerPath: registerPath,
    repoRoot: repoRoot,
  );

  if (result.isClean) {
    stdout.writeln('docs/decisions: clean');
    return;
  }

  for (final diagnostic in result.diagnostics) {
    stderr.writeln(
      'FAIL    ${diagnostic.file}: ${diagnostic.ruleId}: ${diagnostic.message}',
    );
  }
  stderr.writeln('docs/decisions: ${result.diagnostics.length} diagnostic(s)');
  exitCode = 1;
}
