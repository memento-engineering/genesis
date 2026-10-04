import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

void main() {}

/// Shared analyzer fixture with synthetic `genesis_foundation` and
/// `genesis_tree` packages shaped like the published ones.
abstract class TreeRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('genesis_foundation')
      ..addFile('lib/genesis_foundation.dart', r'''
export 'src/annotations.dart';
''')
      ..addFile('lib/src/annotations.dart', r'''
final class DeriveOnly {
  const DeriveOnly();
}

const deriveOnly = DeriveOnly();

final class EffectMarker {
  const EffectMarker();
}

const effect = EffectMarker();

final class EffectLeafMarker {
  const EffectLeafMarker();
}

const effectLeaf = EffectLeafMarker();
''');
    newPackage('genesis_tree').addFile('lib/genesis_tree.dart', r'''
export 'package:genesis_foundation/genesis_foundation.dart';

abstract class BuildContext {
  bool get mounted;
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect});
  T? getInheritedValueOfExactType<T extends Object>();
  void markNeedsRebuild();
}

abstract class HookBuildContext implements BuildContext {}

extension ProviderBuildContext on BuildContext {
  T? watch<T extends Object>() => dependOnInheritedValueOfExactType<T>();
  T? read<T extends Object>() => getInheritedValueOfExactType<T>();
}

abstract class Component {
  const Component();
}

abstract class StatelessComponent extends Component {
  const StatelessComponent();

  Component build(BuildContext context);
}

abstract class HookComponent extends Component {
  const HookComponent();

  Component build(HookBuildContext context);
}

abstract class StatefulComponent extends Component {
  const StatefulComponent();

  State<StatefulComponent> createState();
}

abstract class State<T extends StatefulComponent> {
  T get component => throw 0;

  BuildContext get context => throw 0;

  void initState() {}

  void didChangeDependencies() {}

  Component build(BuildContext context);

  void dispose() {}

  void setState(void Function() fn) {}
}

abstract class SingleChildState<T extends StatefulComponent> extends State<T> {
  Component buildWithChild(BuildContext context, Component child);

  @override
  Component build(BuildContext context) => throw 0;
}

abstract class Element {}
''');
    super.setUp();
    _extendMockAsyncLibrary();
  }

  /// Adds the `dart:async` members the rules match and the mock SDK omits.
  void _extendMockAsyncLibrary() {
    final path = convertPath('${sdkRoot.path}/lib/async/async.dart');
    final source = getFile(path).readAsStringSync();
    const anchor = '  static void run(';
    if (!source.contains(anchor)) {
      throw StateError('The mock dart:async Timer no longer declares run.');
    }
    newFile(
      path,
      '${source.replaceFirst(anchor, '''
  factory Timer.periodic(
    Duration duration,
    void Function(Timer timer) callback,
  ) => throw 0;

$anchor''')}\nvoid scheduleMicrotask(void Function() callback) {}\n',
    );
  }
}
