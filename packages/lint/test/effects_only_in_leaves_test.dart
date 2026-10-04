// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/effects_only_in_leaves.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EffectsOnlyInLeavesRuleTest);
  });
}

const _runtime = r'''
import 'package:genesis_tree/genesis_tree.dart';

@effect
void spawn(String command) {}

abstract interface class Delivery {
  @effect
  void open(String title);
}

final class GitHubDelivery implements Delivery {
  @override
  void open(String title) {}
}

@effect
void spawnTwice(String command) {
  spawn(command);
  spawn(command);
}
''';

@reflectiveTest
final class EffectsOnlyInLeavesRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = EffectsOnlyInLeavesRule();
    super.setUp();
    newFile('$testPackageLibPath/runtime.dart', _runtime);
  }

  Future<void> test_effect_in_a_state() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

import 'runtime.dart';

class Session extends StatefulComponent {
  @override
  State<Session> createState() => _SessionState();
}

class _SessionState extends State<Session> {
  @override
  void initState() {
    spawn('agent');
  }

  @override
  Component build(BuildContext context) => component;
}
''';
    await assertDiagnostics(source, [
      lint(
        source.indexOf('spawn('),
        'spawn'.length,
        messageContainsAll: ["'spawn'"],
      ),
    ]);
  }

  Future<void> test_effect_in_a_top_level_function() async {
    const source = r'''
import 'runtime.dart';

void deliver(Delivery delivery) {
  delivery.open('title');
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('open('), 'open'.length),
    ]);
  }

  Future<void> test_override_of_an_effect() async {
    const source = r'''
import 'runtime.dart';

void deliver(GitHubDelivery delivery) {
  delivery.open('title');
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('open('), 'open'.length),
    ]);
  }

  Future<void> test_effect_in_a_leaf_build() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

import 'runtime.dart';

@effectLeaf
class Spawn extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    spawn('agent');
    return this;
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('spawn('), 'spawn'.length),
    ]);
  }

  Future<void> test_effect_in_a_leaf_outside_its_lifecycle() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

import 'runtime.dart';

@effectLeaf
class SpawnElement {
  SpawnElement(this.delivery) {
    spawn('constructor');
  }

  final Delivery delivery;

  final Object marker = () {
    spawnTwice('initializer');
    return 0;
  }();

  String describe() {
    delivery.open('describe');
    return 'spawn';
  }

  void startOrAdopt() {}
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf("spawn('constructor')"), 'spawn'.length),
      lint(source.indexOf("spawnTwice('initializer')"), 'spawnTwice'.length),
      lint(source.indexOf("open('describe')"), 'open'.length),
    ]);
  }

  Future<void> test_leaf_lifecycle_is_silent() async {
    await assertNoDiagnostics(r'''
import 'package:genesis_tree/genesis_tree.dart';

import 'runtime.dart';

@effectLeaf
abstract class LeafElement extends Element {
  void startOrAdopt();

  void update();

  void dispose();
}

class SpawnElement extends LeafElement {
  SpawnElement(this.delivery);

  final Delivery delivery;

  @override
  void startOrAdopt() {
    spawn('agent');
    _announce();
  }

  @override
  void update() {
    void reopen() => delivery.open('again');
    reopen();
  }

  @override
  void dispose() => _closing.open('closed');

  void _announce() => _greet('started');

  void _greet(String title) => delivery.open(title);

  Delivery get _closing {
    spawn('closing');
    return delivery;
  }
}
''');
  }

  Future<void> test_effects_composing_effects_are_silent() async {
    await assertNoDiagnosticsInFile('$testPackageLibPath/runtime.dart');
  }

  Future<void> test_unannotated_and_lookalike_calls_are_silent() async {
    await assertNoDiagnostics(r'''
const effect = Object();

@effect
void spawn(String command) {}

void log(String message) {}

void run() {
  spawn('agent');
  log('started');
}
''');
  }
}
