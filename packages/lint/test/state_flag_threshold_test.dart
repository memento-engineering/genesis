// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/state_flag_threshold.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(StateFlagThresholdRuleTest);
  });
}

const _preamble = r'''
import 'package:genesis_tree/genesis_tree.dart';

class Session extends StatefulComponent {
  @override
  State<Session> createState() => SessionState();
}
''';

@reflectiveTest
final class StateFlagThresholdRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = StateFlagThresholdRule();
    super.setUp();
  }

  Future<void> test_five_flags() async {
    const source =
        _preamble +
        r'''
class SessionState extends State<Session> {
  bool started = false;
  bool closing = false;
  bool? escalated;
  late bool rearmed;
  final bool dry = true;

  @override
  Component build(BuildContext context) => component;
}
''';
    await assertDiagnostics(source, [
      lint(
        source.indexOf('SessionState extends'),
        'SessionState'.length,
        messageContainsAll: ["'SessionState'", '5 bool fields'],
        correctionContains: 'sealed state value',
      ),
    ]);
  }

  Future<void> test_flags_in_one_declaration() async {
    const source =
        _preamble +
        r'''
class SessionState extends State<Session> {
  bool a = false, b = false, c = false, d = false, e = false;

  @override
  Component build(BuildContext context) => component;
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('SessionState extends'), 'SessionState'.length),
    ]);
  }

  Future<void> test_four_flags_are_silent() async {
    await assertNoDiagnostics(
      _preamble +
          r'''
class SessionState extends State<Session> {
  bool started = false;
  bool closing = false;
  bool? escalated;
  late bool rearmed;
  int attempts = 0;
  static bool verbose = false;
  bool get idle => !started;

  @override
  Component build(BuildContext context) => component;
}
''',
    );
  }

  Future<void> test_non_state_class_is_silent() async {
    await assertNoDiagnostics(r'''
class Options {
  bool a = false, b = false, c = false, d = false, e = false;
}

abstract class State {
  bool a = false, b = false, c = false, d = false, e = false;
}
''');
  }
}
