// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/package_config_file_builder.dart';
import 'package:genesis_lint/src/rules/no_stored_tree_context.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_context_rule_test.dart';

const _holderSource = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Holder {
  TreeContext? saved;

  void store(TreeContext context) {
    saved = context;
  }
}
''';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoStoredTreeContextRuleTest);
  });
}

@reflectiveTest
final class NoStoredTreeContextRuleTest extends TreeContextRuleTest {
  @override
  void setUp() {
    rule = NoStoredTreeContextRule();
    super.setUp();
  }

  Future<void> test_assignment_to_field() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Holder {
  TreeContext? saved;

  void store(TreeContext context) {
    saved = context;
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_collection_add() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

void store(List<TreeContext> values, TreeContext context) {
  values.add(context);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context);'), 'context'.length),
    ]);
  }

  Future<void> test_collection_add_all() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

void store(List<TreeContext> values, Iterable<TreeContext> contexts) {
  values.addAll(contexts);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('contexts);'), 'contexts'.length),
    ]);
  }

  Future<void> test_collection_index_assignment() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

void store(List<TreeContext> values, TreeContext context) {
  values[0] = context;
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_collection_literal() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Object store(TreeContext context) => <TreeContext>[context];
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context];'), 'context'.length),
    ]);
  }

  Future<void> test_conditional_collection_literal() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Object store(bool include, TreeContext context) =>
    <TreeContext>[if (include) context];
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context];'), 'context'.length),
    ]);
  }

  Future<void> test_constructor_field_formal() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Holder {
  Holder(this.context);

  final TreeContext context;
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context);'), 'context'.length),
    ]);
  }

  Future<void> test_constructor_field_initializer() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Holder {
  Holder(TreeContext context) : saved = context;

  final TreeContext saved;
}
''';
    await assertDiagnostics(source, [
      lint(source.lastIndexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_escaping_closure() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Holder {
  late void Function() callback;

  void store(TreeContext context) {
    callback = () {
      context.markNeedsRebuild();
    };
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_returned_closure() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

void Function() store(TreeContext context) {
  return () => context.markNeedsRebuild();
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_closure_inserted_into_collection() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Object store(TreeContext context) => <void Function()>[
  () => context.markNeedsRebuild(),
];
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context.mark'), 'context'.length),
    ]);
  }

  Future<void> test_immediately_invoked_closure() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

void use(TreeContext context) {
  (() => context.markNeedsRebuild())();
}
''');
  }

  Future<void> test_local_same_named_type() async {
    await assertNoDiagnostics(r'''
class TreeContext {}

class Holder {
  TreeContext? saved;

  void store(TreeContext context) {
    saved = context;
  }
}
''');
  }

  Future<void> test_framework_library_owner() async {
    writePackageConfig2(testPackageRootPath, packageName: 'genesis_tree');
    newFile(
      '$testPackageLibPath/genesis_tree.dart',
      getFile('/package/genesis_tree/lib/genesis_tree.dart').readAsStringSync(),
    );
    final path = '$testPackageLibPath/src/fake_holder.dart';
    newFile(path, _holderSource);

    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_managed_branch_owner() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

class FrameworkBranch extends Branch {
  TreeContext? saved;

  void store(TreeContext context) {
    saved = context;
    <TreeContext>[context];
  }
}
''');
  }

  Future<void> test_managed_tree_context_owner() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

class ContextWrapper implements TreeContext {
  ContextWrapper(this.inner);

  final TreeContext inner;

  @override
  bool get mounted => inner.mounted;

  @override
  void markNeedsRebuild() => inner.markNeedsRebuild();
}
''');
  }

  Future<void> test_non_framework_library_owner() async {
    final config = PackageConfigFileBuilder()
      ..add(
        name: 'genesis_tree',
        rootFolder: getFolder('/package/genesis_tree'),
      );
    writePackageConfig2(
      testPackageRootPath,
      packageName: 'app',
      config: config,
    );
    final path = '$testPackageLibPath/holder.dart';
    newFile(path, _holderSource);

    await assertDiagnosticsInFile(path, [
      lint(_holderSource.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_subtype() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

abstract class SpecializedContext implements TreeContext {}

class Holder {
  SpecializedContext? saved;

  void store(SpecializedContext context) {
    saved = context;
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_extension_type_erasure() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

extension type WrappedContext(TreeContext context) {}

void store(List<WrappedContext> values, WrappedContext context) {
  values[0] = context;
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_top_level_setter() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

set retained(TreeContext value) {}

void store(TreeContext context) {
  retained = context;
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('context;'), 'context'.length),
    ]);
  }

  Future<void> test_synchronous_use() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

void use(TreeContext context) {
  context.markNeedsRebuild();
}
''');
  }
}
