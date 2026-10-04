// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/watch_not_read_in_build.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WatchNotReadInBuildRuleTest);
  });
}

const _preamble = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Config {}

class Leaf extends StatelessComponent {
  const Leaf(this.config);

  final Config? config;

  @override
  Component build(BuildContext context) => this;
}
''';

@reflectiveTest
final class WatchNotReadInBuildRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = WatchNotReadInBuildRule();
    super.setUp();
  }

  Future<void> test_snapshot_lookup_in_stateless_build() async {
    const source =
        _preamble +
        r'''
class Reader extends StatelessComponent {
  @override
  Component build(BuildContext context) =>
      Leaf(context.getInheritedValueOfExactType<Config>());
}
''';
    await assertDiagnostics(source, [
      lint(
        source.indexOf('getInheritedValueOfExactType<Config>'),
        'getInheritedValueOfExactType'.length,
      ),
    ]);
  }

  Future<void> test_provider_read_in_state_build() async {
    const source =
        _preamble +
        r'''
class Reader extends StatefulComponent {
  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  @override
  Component build(BuildContext context) => Leaf(context.read<Config>());
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('read<Config>'), 'read'.length),
    ]);
  }

  Future<void> test_snapshot_lookup_in_hook_build() async {
    const source =
        _preamble +
        r'''
class Reader extends HookComponent {
  @override
  Component build(HookBuildContext context) =>
      Leaf(context.getInheritedValueOfExactType<Config>());
}
''';
    await assertDiagnostics(source, [
      lint(
        source.indexOf('getInheritedValueOfExactType<Config>'),
        'getInheritedValueOfExactType'.length,
      ),
    ]);
  }

  Future<void> test_depending_reads_are_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class Reader extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    final watched = context.watch<Config>();
    return Leaf(
      watched ?? context.dependOnInheritedValueOfExactType<Config>(),
    );
  }
}
''',
    );
  }

  Future<void> test_snapshot_reads_outside_build_are_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class Button extends Component {
  const Button(this.onPressed);

  final void Function() onPressed;
}

class Reader extends StatefulComponent {
  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  Config? initial;

  @override
  void initState() {
    initial = context.getInheritedValueOfExactType<Config>();
  }

  @override
  Component build(BuildContext context) =>
      Button(() => context.read<Config>());
}
''',
    );
  }

  Future<void> test_unrelated_read_is_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class Cache {
  Config? read() => null;
}

class Reader extends StatelessComponent {
  const Reader(this.cache);

  final Cache cache;

  @override
  Component build(BuildContext context) => Leaf(cache.read());
}
''',
    );
  }
}
