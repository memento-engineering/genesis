// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/use_tree_context_synchronously.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_context_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseTreeContextSynchronouslyRuleTest);
  });
}

@reflectiveTest
final class UseTreeContextSynchronouslyRuleTest extends TreeContextRuleTest {
  @override
  void setUp() {
    rule = UseTreeContextSynchronouslyRule();
    super.setUp();
  }

  Future<void> test_after_await() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  context.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_guarded_after_await() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  if (!context.mounted) return;
  context.markNeedsRebuild();
}
''');
  }

  Future<void> test_guarded_by_false_comparison() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  if (context.mounted == false) {
    throw 'unmounted';
  }
  context.markNeedsRebuild();
}
''');
  }

  Future<void> test_guarded_positive_branch() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  if (context.mounted) {
    context.markNeedsRebuild();
  }
}
''');
  }

  Future<void> test_second_await_invalidates_guard() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  if (!context.mounted) return;
  await Future<void>.value();
  context.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_guard_for_another_handle() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext first, TreeContext second) async {
  await Future<void>.value();
  if (!first.mounted) return;
  second.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('second.mark'), 'second'.length),
    ]);
  }

  Future<void> test_mounted_probe_is_safe() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<bool> use(TreeContext context) async {
  await Future<void>.value();
  return context.mounted;
    }
''');
  }

  Future<void> test_executable_return_type() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

TreeContext acquire() => throw 'fixture';

Future<void> use() async {
  await Future<void>.value();
  acquire().markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('acquire().mark'), 'acquire'.length),
    ]);
  }

  Future<void> test_nested_closure_has_own_boundary() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(TreeContext context) async {
  await Future<void>.value();
  (() => context.markNeedsRebuild())();
}
''');
  }

  Future<void> test_no_async_gap() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

void use(TreeContext context) {
  context.markNeedsRebuild();
}
''');
  }
}
