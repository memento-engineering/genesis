// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/no_future_callback_chains.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/async_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoFutureCallbackChainsRuleTest);
  });
}

@reflectiveTest
final class NoFutureCallbackChainsRuleTest extends AsyncRuleTest {
  @override
  void setUp() {
    rule = NoFutureCallbackChainsRule();
    super.setUp();
  }

  Future<void> test_then_on_future() async {
    const source = r'''
void f(Future<int> x) {
  x.then((v) => v + 1);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_catchError_on_future() async {
    const source = r'''
void f(Future<int> x) {
  x.catchError((Object e) => 0);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('catchError('), 'catchError'.length),
    ]);
  }

  Future<void> test_whenComplete_on_future() async {
    const source = r'''
void f(Future<int> x) {
  x.whenComplete(() {});
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('whenComplete('), 'whenComplete'.length),
    ]);
  }

  Future<void> test_onError_on_future() async {
    const source = r'''
import 'dart:async';

void f(Future<int> x) {
  x.onError<Object>((e, s) => 0);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('onError<'), 'onError'.length),
    ]);
  }

  Future<void> test_then_on_subtype_of_future() async {
    const source = r'''
abstract class Deferred<T> implements Future<T> {}

void f(Deferred<int> x) {
  x.then((v) => v + 1);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_on_future_or_narrowed_to_future() async {
    const source = r'''
import 'dart:async';

void f(FutureOr<int> v) {
  if (v is Future<int>) {
    v.then((x) => x + 1);
  }
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_on_nullable_future() async {
    const source = r'''
void f(Future<int>? x) {
  x?.then((v) => v + 1);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_on_type_variable_bounded_by_future() async {
    const source = r'''
void f<F extends Future<int>>(F x) {
  x.then((v) => v + 1);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_through_cascade() async {
    const source = r'''
void f(Future<int> x) {
  x..then((v) => v + 1);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_with_on_error_argument_reports_once() async {
    const source = r'''
void f(Future<int> x) {
  x.then((v) => v + 1, onError: (Object e) => 0);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }

  Future<void> test_then_then_catchError_reports_twice() async {
    const source = r'''
void f(Future<int> x) {
  x.then((v) => v + 1).catchError((Object e) => 0);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('then('), 'then'.length),
      lint(source.indexOf('catchError('), 'catchError'.length),
    ]);
  }

  Future<void> test_future_wait_is_silent() async {
    await assertNoDiagnostics(r'''
Future<void> f(Future<int> a, Future<int> b) async {
  await Future.wait([a, b]);
}
''');
  }

  Future<void> test_future_value_is_silent() async {
    await assertNoDiagnostics(r'''
Future<int> f() => Future.value(1);
''');
  }

  Future<void> test_timeout_is_silent() async {
    await assertNoDiagnostics(r'''
Future<int> f(Future<int> x) => x.timeout(const Duration(seconds: 1));
''');
  }

  Future<void> test_ignore_is_silent() async {
    await assertNoDiagnostics(r'''
import 'dart:async';

void f(Future<int> x) {
  x.ignore();
}
''');
  }

  Future<void> test_then_on_non_future_class_is_silent() async {
    await assertNoDiagnostics(r'''
class Thenable {
  void then(void Function(int) onValue) {}
}

void f(Thenable x) {
  x.then((v) {});
}
''');
  }

  Future<void> test_stream_listen_on_error_is_silent() async {
    await assertNoDiagnostics(r'''
void f() {
  Stream.fromIterable([1]).listen((_) {}, onError: (Object _) {});
}
''');
  }

  Future<void> test_dynamic_receiver_is_silent() async {
    await assertNoDiagnostics(r'''
void f(dynamic x) {
  x.then((v) => v);
}
''');
  }

  Future<void> test_tear_off_is_silent() async {
    await assertNoDiagnostics(r'''
Object f(Future<int> x) => x.then;
''');
  }

  Future<void> test_await_in_try_catch_is_silent() async {
    await assertNoDiagnostics(r'''
Future<void> f(Future<int> x) async {
  try {
    await x;
  } on Object catch (_) {}
}
''');
  }

  Future<void> test_reports_in_test_directory() async {
    const source = r'''
void f(Future<int> x) {
  x.then((v) => v + 1);
}
''';
    final path = '$testPackageRootPath/test/chain_test.dart';
    newFile(path, source);

    await assertDiagnosticsInFile(path, [
      lint(source.indexOf('then('), 'then'.length),
    ]);
  }
}
