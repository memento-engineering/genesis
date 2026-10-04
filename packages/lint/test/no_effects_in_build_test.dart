// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/no_effects_in_build.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoEffectsInBuildRuleTest);
  });
}

const _leaf = r'''
class Leaf extends StatelessComponent {
  const Leaf();

  @override
  Component build(BuildContext context) => this;
}
''';

@reflectiveTest
final class NoEffectsInBuildRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = NoEffectsInBuildRule();
    super.setUp();
  }

  Future<void> test_future_returning_call() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Loader extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    load();
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('load();'), 'load()'.length),
    ]);
  }

  Future<void> test_future_or_returning_method() async {
    const source =
        r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

class Loader extends StatelessComponent {
  FutureOr<int> count() => 1;

  @override
  Component build(BuildContext context) {
    count();
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('count();'), 'count()'.length),
    ]);
  }

  Future<void> test_future_delayed_constructor() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

class Loader extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    Future<void>.delayed(Duration.zero);
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(
        source.indexOf('Future<void>.delayed'),
        'Future<void>.delayed(Duration.zero)'.length,
      ),
    ]);
  }

  Future<void> test_timer_constructors() async {
    const source =
        r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

class Ticker extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    Timer(Duration.zero, () {});
    Timer.periodic(Duration.zero, (_) {});
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(
        source.indexOf('Timer(Duration'),
        'Timer(Duration.zero, () {})'.length,
      ),
      lint(
        source.indexOf('Timer.periodic'),
        'Timer.periodic(Duration.zero, (_) {})'.length,
      ),
    ]);
  }

  Future<void> test_schedule_microtask() async {
    const source =
        r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

class Scheduler extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    scheduleMicrotask(() {});
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(
        source.indexOf('scheduleMicrotask('),
        'scheduleMicrotask(() {})'.length,
      ),
    ]);
  }

  Future<void> test_field_writes_in_state_build() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class Box {
  int value = 0;
}

class _CounterState extends State<Counter> {
  int builds = 0;
  final Box box = Box();
  final Map<String, int> seen = {};

  @override
  Component build(BuildContext context) {
    builds = 1;
    box.value = 2;
    seen['a'] = 3;
    builds++;
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('builds = 1'), 'builds'.length),
      lint(source.indexOf('box.value = 2'), 'box.value'.length),
      lint(source.indexOf("seen['a']"), "seen['a']".length),
      lint(source.indexOf('builds++'), 'builds'.length),
    ]);
  }

  Future<void> test_set_state_in_build() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  @override
  Component build(BuildContext context) {
    setState(() {});
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('setState('), 'setState(() {})'.length),
    ]);
  }

  Future<void> test_build_with_child() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Wrapper extends StatefulComponent {
  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends SingleChildState<Wrapper> {
  @override
  Component buildWithChild(BuildContext context, Component child) {
    load();
    return child;
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('load();'), 'load()'.length),
    ]);
  }

  Future<void> test_hook_component_build() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Hooked extends HookComponent {
  @override
  Component build(HookBuildContext context) {
    load();
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('load();'), 'load()'.length),
    ]);
  }

  Future<void> test_immediately_invoked_closure() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Loader extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    (() {
      load();
    })();
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('load();'), 'load()'.length),
    ]);
  }

  Future<void> test_timer_run_and_future_wait() async {
    const source =
        r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

class Waiter extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    Timer.run(() {});
    Future.wait(<Future<int>>[]);
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('Timer.run'), 'Timer.run(() {})'.length),
      lint(
        source.indexOf('Future.wait'),
        'Future.wait(<Future<int>>[])'.length,
      ),
    ]);
  }

  Future<void> test_await_in_an_async_build() async {
    const source = r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<int> load() async => 1;

class Loader extends Component {
  Future<int> build() async {
    return await load();
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('await load()'), 'await load()'.length),
      lint(source.indexOf('load();'), 'load()'.length),
    ]);
  }

  Future<void> test_cascade_writes_to_durable_receivers() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class Box {
  int value = 0;
}

class _CounterState extends State<Counter> {
  final Box box = Box();
  final Map<String, int> seen = {};

  @override
  Component build(BuildContext context) {
    box..value = 1;
    seen..['a'] = 2;
    (box).value = 3;
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('..value = 1'), '..value'.length),
      lint(source.indexOf("..['a'] = 2"), "..['a']".length),
      lint(source.indexOf('(box).value'), '(box).value'.length),
    ]);
  }

  Future<void> test_effects_in_synchronous_callbacks() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<int> load(int id) async => id;

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;
  final List<int> ids = [1, 2];

  @override
  Component build(BuildContext context) {
    ids.forEach((id) {
      count = id;
    });
    ids.map((id) => load(id)).toList();
    final total = ids.fold<int>(0, (sum, id) => sum + (count = id));
    return total > 0 ? const Leaf() : const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('count = id;'), 'count'.length),
      lint(source.indexOf('load(id)'), 'load(id)'.length),
      lint(source.indexOf('count = id)'), 'count'.length),
    ]);
  }

  Future<void> test_effects_in_called_local_functions() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

Future<int> load(int id) async => id;

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;
  final List<int> ids = [1, 2];

  @override
  Component build(BuildContext context) {
    void remember(int id) {
      count = id;
    }

    void fetch(int id) => load(id);
    remember(1);
    remember(2);
    ids.forEach(fetch);
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('count = id;'), 'count'.length),
      lint(source.indexOf('load(id)'), 'load(id)'.length),
    ]);
  }

  Future<void> test_stream_listen() async {
    const source =
        r'''
import 'package:genesis_tree/genesis_tree.dart';

class Watcher extends StatelessComponent {
  const Watcher(this.ticks);

  final Stream<int> ticks;

  @override
  Component build(BuildContext context) {
    ticks.listen((_) {});
    return const Leaf();
  }
}
''' +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('ticks.listen'), 'ticks.listen((_) {})'.length),
    ]);
  }

  Future<void> test_local_and_fresh_receivers_are_silent() async {
    await assertNoDiagnostics(
      r'''
import 'package:genesis_tree/genesis_tree.dart';

class Bag {
  int x = 0;
}

class Row extends Component {
  const Row(this.children, this.weights);

  final List<Component> children;
  final Map<String, int> weights;
}

class Rows extends StatelessComponent {
  const Rows(this.names);

  final List<String> names;

  @override
  Component build(BuildContext context) {
    final weights = <String, int>{}..['a'] = 1;
    final children = <Component>[]..length = 0;
    final bag = Bag();
    bag.x = 1;
    (Bag()..x = 2).x = 3;
    final counts = {for (final name in names) name: 0};
    names.forEach((name) => counts[name] = name.length);
    final sorted = names.where((name) => name.isNotEmpty).toList();
    final labels = List<String>.generate(sorted.length, (i) {
      final label = Bag();
      label.x = i;
      return '${label.x}';
    });
    weights['b'] = labels.length + bag.x;
    return Row(children, weights);
  }
}
''' +
          _leaf,
    );
  }

  Future<void> test_fold_into_a_fresh_accumulator_is_silent() async {
    await assertNoDiagnostics(
      r"""
import 'package:genesis_tree/genesis_tree.dart';

class Row extends Component {
  const Row(this.weights);

  final Map<String, int> weights;
}

class Rows extends StatelessComponent {
  const Rows(this.names);

  final List<String> names;

  @override
  Component build(BuildContext context) {
    final weights = names.fold(
      <String, int>{},
      (acc, name) => acc..[name] = name.length,
    );
    final seed = <String>[];
    final joined = names.fold<List<String>>(seed, (acc, name) {
      acc.add(name);
      acc[0] = name;
      return acc;
    });
    final boxes = names.fold(Box(), (box, name) => box..length = name.length);
    return Row({...weights, 'n': joined.length + boxes.length});
  }
}

class Box {
  int length = 0;
}
""" +
          _leaf,
    );
  }

  Future<void> test_durable_writes_in_a_fold_callback() async {
    const source =
        r"""
import 'package:genesis_tree/genesis_tree.dart';

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int last = 0;
  final Map<String, int> seen = {};
  final List<String> names = ['a'];

  @override
  Component build(BuildContext context) {
    names.fold(<String, int>{}, (acc, name) {
      last = name.length;
      return acc..[name] = 1;
    });
    names.fold(seen, (acc, name) => acc..[name] = 2);
    names.fold(<String, int>{}, (acc, name) => seen..[name] = 3);
    return const Leaf();
  }
}
""" +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('last = name'), 'last'.length),
      lint(source.indexOf('..[name] = 2'), '..[name]'.length),
      lint(source.indexOf('..[name] = 3'), '..[name]'.length),
    ]);
  }

  Future<void> test_lazy_iterable_callbacks_are_checked() async {
    const source =
        r"""
import 'package:genesis_tree/genesis_tree.dart';

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int last = 0;
  final List<int> ids = [1];

  @override
  Component build(BuildContext context) {
    ids.where((id) => (last = id) > 0);
    return const Leaf();
  }
}
""" +
        _leaf;
    await assertDiagnostics(source, [
      lint(source.indexOf('last = id'), 'last'.length),
    ]);
  }

  Future<void> test_pure_build_is_silent() async {
    await assertNoDiagnostics(
      r'''
import 'package:genesis_tree/genesis_tree.dart';

class Row extends Component {
  const Row(this.children);

  final List<Component> children;
}

class Rows extends StatelessComponent {
  const Rows(this.count);

  final int count;

  @override
  Component build(BuildContext context) {
    final children = <Component>[];
    var index = 0;
    while (index < count) {
      children.add(const Leaf());
      index++;
    }
    final slots = List<Component?>.filled(1, null);
    slots[0] = const Leaf();
    return Row(children);
  }
}
''' +
          _leaf,
    );
  }

  Future<void> test_deferred_closures_are_silent() async {
    await assertNoDiagnostics(r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Button extends Component {
  const Button(this.onPressed);

  final void Function() onPressed;
}

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int taps = 0;

  @override
  Component build(BuildContext context) {
    void later() => load();
    return Button(() {
      setState(() => taps++);
      Timer(Duration.zero, later);
    });
  }
}
''');
  }

  Future<void> test_effects_outside_build_are_silent() async {
    await assertNoDiagnostics(
      r'''
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

Future<void> load() async {}

class Counter extends StatefulComponent {
  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  Timer? timer;

  @override
  void initState() {
    timer = Timer(Duration.zero, () {});
    load();
  }

  @override
  Component build(BuildContext context) => const Leaf();
}
''' +
          _leaf,
    );
  }

  Future<void> test_unrelated_build_method_is_silent() async {
    await assertNoDiagnostics(r'''
Future<void> load() async {}

abstract class Component {}

abstract class State {
  Component build();
}

class Loader extends State {
  int builds = 0;

  @override
  Component build() {
    builds = 1;
    load();
    throw 0;
  }
}
''');
  }
}
