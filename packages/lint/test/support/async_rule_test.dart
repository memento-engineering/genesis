import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

void main() {}

/// Shared analyzer fixture whose mock `dart:async` declares the `Future`
/// members the async rules match and the mock SDK omits: `timeout`, and the
/// `FutureExtensions` members `onError` and `ignore`.
abstract class AsyncRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    super.setUp();
    _extendMockAsyncLibrary();
  }

  void _extendMockAsyncLibrary() {
    final path = convertPath('${sdkRoot.path}/lib/async/async.dart');
    final source = getFile(path).readAsStringSync();
    const anchor = '  Future<T> whenComplete(';
    if (!source.contains(anchor)) {
      throw StateError(
        'The mock dart:async Future no longer declares '
        'whenComplete.',
      );
    }
    newFile(
      path,
      '${source.replaceFirst(anchor, '''
  Future<T> timeout(Duration timeLimit, {FutureOr<T> onTimeout()?});

$anchor''')}\n'
      'extension FutureExtensions<T> on Future<T> {\n'
      '  Future<T> onError<E extends Object>(\n'
      '    FutureOr<T> handleError(E error, StackTrace stackTrace), {\n'
      '    bool test(E error)?,\n'
      '  }) => throw 0;\n'
      '\n'
      '  void ignore() {}\n'
      '}\n',
    );
  }
}
