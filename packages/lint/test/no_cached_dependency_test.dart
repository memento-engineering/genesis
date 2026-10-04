// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/no_cached_dependency.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoCachedDependencyRuleTest);
  });
}

const _preamble = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Config {}

class Service {
  Service(this.config);

  static Service of(BuildContext context) => throw 0;

  final Config? config;
}

class Host extends StatefulComponent {
  @override
  State<Host> createState() => _HostState();
}
''';

@reflectiveTest
final class NoCachedDependencyRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = NoCachedDependencyRule();
    super.setUp();
  }

  Future<void> test_depend_on_inherited_value() async {
    const source =
        _preamble +
        r'''
class _HostState extends State<Host> {
  Config? config;

  @override
  Component build(BuildContext context) {
    config ??= context.dependOnInheritedValueOfExactType<Config>();
    return component;
  }
}
''';
    const assignment =
        'config ??= context.dependOnInheritedValueOfExactType<Config>()';
    await assertDiagnostics(source, [
      lint(source.indexOf(assignment), assignment.length),
    ]);
  }

  Future<void> test_snapshot_read_in_lifecycle() async {
    const source =
        _preamble +
        r'''
class _HostState extends State<Host> {
  Config? config;

  @override
  void initState() {
    config ??= context.getInheritedValueOfExactType<Config>();
  }

  @override
  Component build(BuildContext context) => component;
}
''';
    const assignment =
        'config ??= context.getInheritedValueOfExactType<Config>()';
    await assertDiagnostics(source, [
      lint(source.indexOf(assignment), assignment.length),
    ]);
  }

  Future<void> test_provider_watch_and_read() async {
    const source =
        _preamble +
        r'''
class _HostState extends State<Host> {
  Config? watched;
  Config? read;

  @override
  void didChangeDependencies() {
    watched ??= context.watch<Config>();
    read ??= context.read<Config>();
  }

  @override
  Component build(BuildContext context) => component;
}
''';
    const watched = 'watched ??= context.watch<Config>()';
    const read = 'read ??= context.read<Config>()';
    await assertDiagnostics(source, [
      lint(source.indexOf(watched), watched.length),
      lint(source.indexOf(read), read.length),
    ]);
  }

  Future<void> test_invocation_taking_a_context() async {
    const source =
        _preamble +
        r'''
class _HostState extends State<Host> {
  Service? service;

  @override
  Component build(BuildContext context) {
    service ??= Service.of(context);
    return component;
  }
}
''';
    const assignment = 'service ??= Service.of(context)';
    await assertDiagnostics(source, [
      lint(source.indexOf(assignment), assignment.length),
    ]);
  }

  Future<void> test_nested_read_inside_a_construction() async {
    const source =
        _preamble +
        r'''
class _HostState extends State<Host> {
  Service? service;

  @override
  Component build(BuildContext context) {
    service ??= Service(context.watch<Config>());
    return component;
  }
}
''';
    const assignment = 'service ??= Service(context.watch<Config>())';
    await assertDiagnostics(source, [
      lint(source.indexOf(assignment), assignment.length),
    ]);
  }

  Future<void> test_top_level_cache() async {
    const source =
        _preamble +
        r'''
Config? cached;

void remember(BuildContext context) {
  cached ??= context.read<Config>();
}

class _HostState extends State<Host> {
  @override
  Component build(BuildContext context) => component;
}
''';
    const assignment = 'cached ??= context.read<Config>()';
    await assertDiagnostics(source, [
      lint(source.indexOf(assignment), assignment.length),
    ]);
  }

  Future<void> test_cached_handle_wrapper_is_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
abstract class DomainContext implements BuildContext {}

DomainContext wrap(BuildContext inner) => throw 0;

class DomainElement extends Element {
  DomainElement(this.inner);

  final BuildContext inner;

  DomainContext? _handle;

  DomainContext get context => _handle ??= wrap(inner);
}

class _HostState extends State<Host> {
  @override
  Component build(BuildContext context) => component;
}
''',
    );
  }

  Future<void> test_local_null_assignment_is_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class _HostState extends State<Host> {
  int? count;

  @override
  Component build(BuildContext context) {
    Config? config;
    config ??= context.watch<Config>();
    count ??= 0;
    return component;
  }
}
''',
    );
  }

  Future<void> test_deferred_closure_is_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class _HostState extends State<Host> {
  Config? Function()? reader;

  @override
  Component build(BuildContext context) {
    reader ??= () => Config();
    return component;
  }
}
''',
    );
  }

  Future<void> test_unrelated_context_type_is_silent() async {
    await assertNoDiagnostics(r'''
class BuildContext {
  T? read<T>() => null;
}

class Holder {
  int? value;

  void remember(BuildContext context) {
    value ??= context.read<int>();
  }
}
''');
  }
}
