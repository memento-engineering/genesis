// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/use_build_context_synchronously.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/build_context_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UseBuildContextSynchronouslyRuleTest);
  });
}

@reflectiveTest
final class UseBuildContextSynchronouslyRuleTest extends BuildContextRuleTest {
  @override
  void setUp() {
    rule = UseBuildContextSynchronouslyRule();
    super.setUp();
  }

  Future<void> test_after_await() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(BuildContext context) async {
  await Future<void>.value();
  context.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_legacy_alias_after_await() async {
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

  Future<void> test_prefixed_mixed_aliases_after_await() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart' as tree;

Future<void> use(
  tree.BuildContext canonical,
  tree.TreeContext legacy,
) async {
  await Future<void>.value();
  canonical.markNeedsRebuild();
  legacy.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('canonical.mark'), 'canonical'.length),
      lint(source.indexOf('legacy.mark'), 'legacy'.length),
    ]);
  }

  Future<void> test_guarded_after_await() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(BuildContext context) async {
  await Future<void>.value();
  if (!context.mounted) return;
  context.markNeedsRebuild();
}
''');
  }

  Future<void> test_guarded_by_false_comparison() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> use(BuildContext context) async {
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

Future<void> use(BuildContext context) async {
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

Future<void> use(BuildContext context) async {
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

Future<void> use(BuildContext first, BuildContext second) async {
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

Future<bool> use(BuildContext context) async {
  await Future<void>.value();
  return context.mounted;
    }
''');
  }

  Future<void> test_executable_return_type() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

BuildContext acquire() => throw 'fixture';

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

Future<void> use(BuildContext context) async {
  await Future<void>.value();
  (() => context.markNeedsRebuild())();
}
''');
  }

  Future<void> test_no_async_gap() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

void use(BuildContext context) {
  context.markNeedsRebuild();
}
''');
  }
}
