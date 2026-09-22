import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

final class _Source1 {
  const _Source1(this.value);
  final int value;
}

final class _Source2 {
  const _Source2(this.value);
  final int value;
}

final class _Source3 {
  const _Source3(this.value);
  final int value;
}

final class _Source4 {
  const _Source4(this.value);
  final int value;
}

final class _Source5 {
  const _Source5(this.value);
  final int value;
}

final class _Source6 {
  const _Source6(this.value);
  final int value;
}

final class _Derived {
  _Derived(Iterable<int> values) : values = List.unmodifiable(values);

  final List<int> values;
}

final class _UpdateCall {
  const _UpdateCall({
    required this.values,
    required this.previous,
    required this.result,
  });

  final List<int> values;
  final _Derived? previous;
  final _Derived result;
}

_Derived _derive(
  List<_UpdateCall> calls,
  List<int> values,
  _Derived? previous,
) {
  final result = _Derived(values);
  calls.add(_UpdateCall(values: values, previous: previous, result: result));
  return result;
}

final class _Leaf extends Component {
  const _Leaf();

  @override
  Element createElement() => _LeafElement(this);
}

final class _LeafElement extends Element {
  _LeafElement(_Leaf super.component);
}

final class _DerivedWatch extends StatelessComponent {
  const _DerivedWatch(this.observations);

  final List<List<int>?> observations;

  @override
  Component build(BuildContext context) {
    observations.add(context.watch<_Derived>()?.values);
    return const _Leaf();
  }
}

/// A stable six-source ancestor. Updating one slot retains the other five
/// identities and never re-describes [child], so only that dependency edge
/// dirties the proxy under test.
final class _Sources extends StatefulComponent {
  const _Sources({required this.onCreate, required this.child});

  final void Function(_SourcesState state) onCreate;
  final Component child;

  @override
  State<_Sources> createState() {
    final state = _SourcesState();
    onCreate(state);
    return state;
  }
}

final class _SourcesState extends State<_Sources> {
  _Source1 _source1 = const _Source1(1);
  _Source2 _source2 = const _Source2(2);
  _Source3 _source3 = const _Source3(3);
  _Source4 _source4 = const _Source4(4);
  _Source5 _source5 = const _Source5(5);
  _Source6 _source6 = const _Source6(6);

  void change(int source, int value) {
    setState(() {
      switch (source) {
        case 1:
          _source1 = _Source1(value);
        case 2:
          _source2 = _Source2(value);
        case 3:
          _source3 = _Source3(value);
        case 4:
          _source4 = _Source4(value);
        case 5:
          _source5 = _Source5(value);
        case 6:
          _source6 = _Source6(value);
        default:
          throw ArgumentError.value(source, 'source');
      }
    });
  }

  @override
  Component build(BuildContext context) => Nest(
    children: [
      Provider<_Source1>.value(_source1),
      Provider<_Source2>.value(_source2),
      Provider<_Source3>.value(_source3),
      Provider<_Source4>.value(_source4),
      Provider<_Source5>.value(_source5),
      Provider<_Source6>.value(_source6),
    ],
    child: component.child,
  );
}

final class _Host extends StatefulComponent {
  const _Host({required this.onCreate, required this.describe});

  final void Function(_HostState state) onCreate;
  final Component Function() describe;

  @override
  State<_Host> createState() {
    final state = _HostState();
    onCreate(state);
    return state;
  }
}

final class _HostState extends State<_Host> {
  Component Function()? _override;

  void swap(Component Function() describe) =>
      setState(() => _override = describe);

  @override
  Component build(BuildContext context) => (_override ?? component.describe)();
}

final class _Slots extends MultiChildComponent {
  _Slots(List<Component> children) : super(children: children);
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

final class _DerivedTeardownRead extends StatefulComponent {
  const _DerivedTeardownRead(this.events);

  final List<String> events;

  @override
  State<_DerivedTeardownRead> createState() => _DerivedTeardownReadState();
}

final class _DerivedTeardownReadState extends State<_DerivedTeardownRead> {
  @override
  Component build(BuildContext context) => const _Leaf();

  @override
  void dispose() {
    component.events.add(
      'teardown read ${context.read<_Derived>()?.values.single}',
    );
  }
}

final class _OwnedResult {
  const _OwnedResult(this.name);

  final String name;
}

final class _AdoptedSource {
  _AdoptedSource(this.value, this.events);

  final int value;
  final List<String> events;
  bool disposed = false;

  void dispose() {
    disposed = true;
    events.add('dispose adopted $value');
  }
}

final class _AdoptedSourceHost extends StatefulComponent {
  const _AdoptedSourceHost({
    required this.initial,
    required this.onCreate,
    required this.child,
  });

  final _AdoptedSource initial;
  final void Function(_AdoptedSourceHostState state) onCreate;
  final Component child;

  @override
  State<_AdoptedSourceHost> createState() {
    final state = _AdoptedSourceHostState();
    onCreate(state);
    return state;
  }
}

final class _AdoptedSourceHostState extends State<_AdoptedSourceHost> {
  late _AdoptedSource _source;

  @override
  void initState() => _source = component.initial;

  void update(_AdoptedSource source) => setState(() => _source = source);

  @override
  Component build(BuildContext context) =>
      Provider<_AdoptedSource>.value(_source, child: component.child);
}

final class _OwnedWatch extends StatelessComponent {
  const _OwnedWatch(this.observations);

  final List<String?> observations;

  @override
  Component build(BuildContext context) {
    observations.add(context.watch<_OwnedResult>()?.name);
    return const _Leaf();
  }
}

void main() {
  test('arity 1 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy = ProxyProvider<_Source1, _Derived>(
      update: (_, value, previous) => _derive(calls, [value.value], previous),
      child: _DerivedWatch(observations),
    );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1]);
    expect(calls.single.previous, isNull);
    expect(observations, [
      [1],
    ]);

    final first = calls.single.result;
    sources.change(1, 11);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [11]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [11]);
  });

  test('arity 2 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy = ProxyProvider2<_Source1, _Source2, _Derived>(
      update: (_, value1, value2, previous) =>
          _derive(calls, [value1.value, value2.value], previous),
      child: _DerivedWatch(observations),
    );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1, 2]);
    expect(calls.single.previous, isNull);

    final first = calls.single.result;
    sources.change(2, 22);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [1, 22]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [1, 22]);
  });

  test('arity 3 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy = ProxyProvider3<_Source1, _Source2, _Source3, _Derived>(
      update: (_, value1, value2, value3, previous) =>
          _derive(calls, [value1.value, value2.value, value3.value], previous),
      child: _DerivedWatch(observations),
    );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1, 2, 3]);
    expect(calls.single.previous, isNull);

    final first = calls.single.result;
    sources.change(3, 33);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [1, 2, 33]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [1, 2, 33]);
  });

  test('arity 4 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy =
        ProxyProvider4<_Source1, _Source2, _Source3, _Source4, _Derived>(
          update: (_, value1, value2, value3, value4, previous) => _derive(
            calls,
            [value1.value, value2.value, value3.value, value4.value],
            previous,
          ),
          child: _DerivedWatch(observations),
        );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1, 2, 3, 4]);
    expect(calls.single.previous, isNull);

    final first = calls.single.result;
    sources.change(4, 44);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [1, 2, 3, 44]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [1, 2, 3, 44]);
  });

  test('arity 5 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy =
        ProxyProvider5<
          _Source1,
          _Source2,
          _Source3,
          _Source4,
          _Source5,
          _Derived
        >(
          update: (_, value1, value2, value3, value4, value5, previous) =>
              _derive(calls, [
                value1.value,
                value2.value,
                value3.value,
                value4.value,
                value5.value,
              ], previous),
          child: _DerivedWatch(observations),
        );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1, 2, 3, 4, 5]);
    expect(calls.single.previous, isNull);

    final first = calls.single.result;
    sources.change(5, 55);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [1, 2, 3, 4, 55]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [1, 2, 3, 4, 55]);
  });

  test('arity 6 rebuilds after a watched ancestor changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy =
        ProxyProvider6<
          _Source1,
          _Source2,
          _Source3,
          _Source4,
          _Source5,
          _Source6,
          _Derived
        >(
          update:
              (_, value1, value2, value3, value4, value5, value6, previous) =>
                  _derive(calls, [
                    value1.value,
                    value2.value,
                    value3.value,
                    value4.value,
                    value5.value,
                    value6.value,
                  ], previous),
          child: _DerivedWatch(observations),
        );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    expect(calls.single.values, [1, 2, 3, 4, 5, 6]);
    expect(calls.single.previous, isNull);

    final first = calls.single.result;
    sources.change(6, 66);
    owner.flush();
    expect(calls, hasLength(2));
    expect(calls.last.values, [1, 2, 3, 4, 5, 66]);
    expect(calls.last.previous, same(first));
    expect(observations.last, [1, 2, 3, 4, 5, 66]);
  });

  test('ProxyProvider3 rebuilds when each declared dependency changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy = ProxyProvider3<_Source1, _Source2, _Source3, _Derived>(
      update: (_, value1, value2, value3, previous) =>
          _derive(calls, [value1.value, value2.value, value3.value], previous),
      child: _DerivedWatch(observations),
    );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    final expected = [1, 2, 3];
    for (var source = 1; source <= 3; source++) {
      expected[source - 1] = 100 + source;
      sources.change(source, 100 + source);
      owner.flush();
      expect(calls, hasLength(source + 1));
      expect(calls.last.values, expected);
      expect(observations.last, expected);
    }
  });

  test('ProxyProvider6 rebuilds when each declared dependency changes', () {
    final calls = <_UpdateCall>[];
    final observations = <List<int>?>[];
    late _SourcesState sources;
    final proxy =
        ProxyProvider6<
          _Source1,
          _Source2,
          _Source3,
          _Source4,
          _Source5,
          _Source6,
          _Derived
        >(
          update:
              (_, value1, value2, value3, value4, value5, value6, previous) =>
                  _derive(calls, [
                    value1.value,
                    value2.value,
                    value3.value,
                    value4.value,
                    value5.value,
                    value6.value,
                  ], previous),
          child: _DerivedWatch(observations),
        );
    final owner = BuildOwner();
    addTearDown(owner.dispose);

    owner.mountRoot(
      ProviderScope(
        child: _Sources(onCreate: (state) => sources = state, child: proxy),
      ),
    );
    final expected = [1, 2, 3, 4, 5, 6];
    for (var source = 1; source <= 6; source++) {
      expected[source - 1] = 100 + source;
      sources.change(source, 100 + source);
      owner.flush();
      expect(calls, hasLength(source + 1));
      expect(calls.last.values, expected);
      expect(observations.last, expected);
    }
  });

  test('shared machinery disposes after descendant teardown', () {
    final events = <String>[];
    final owner = BuildOwner();

    owner.mountRoot(
      Nest(
        children: [
          Provider<_Source1>(
            create: (_) {
              events.add('create outer');
              return const _Source1(7);
            },
            dispose: (value) => events.add('dispose outer ${value.value}'),
          ),
          ProxyProvider<_Source1, _Derived>(
            update: (_, source, previous) {
              events.add('update proxy');
              return _Derived([source.value]);
            },
            dispose: (value) =>
                events.add('dispose proxy ${value.values.single}'),
          ),
        ],
        child: _DerivedTeardownRead(events),
      ),
    );
    expect(events, ['create outer', 'update proxy']);

    owner.dispose();
    expect(events, [
      'create outer',
      'update proxy',
      'teardown read 7',
      'dispose proxy 7',
      'dispose outer 7',
    ]);
  });

  test('owned replacements dispose once and adopted sources never dispose', () {
    final events = <String>[];
    final observations = <String?>[];
    final adopted = [
      _AdoptedSource(1, events),
      _AdoptedSource(2, events),
      _AdoptedSource(3, events),
    ];
    late _AdoptedSourceHostState sources;
    final proxy = ProxyProvider<_AdoptedSource, _OwnedResult>(
      create: (_) {
        events.add('create component');
        return const _OwnedResult('component');
      },
      update: (_, source, previous) {
        events.add('update ${source.value} previous ${previous?.name}');
        if (source.value == 3) return previous!;
        return _OwnedResult(source.value == 1 ? 'first' : 'second');
      },
      dispose: (value) => events.add('dispose ${value.name}'),
      child: _OwnedWatch(observations),
    );
    final owner = BuildOwner();

    owner.mountRoot(
      _AdoptedSourceHost(
        initial: adopted[0],
        onCreate: (state) => sources = state,
        child: proxy,
      ),
    );
    expect(events, [
      'create component',
      'update 1 previous component',
      'dispose component',
    ]);
    expect(observations, ['first']);

    sources.update(adopted[1]);
    owner.flush();
    expect(events, [
      'create component',
      'update 1 previous component',
      'dispose component',
      'update 2 previous first',
      'dispose first',
    ]);
    expect(observations.last, 'second');

    sources.update(adopted[2]);
    owner.flush();
    expect(events.last, 'update 3 previous second');
    expect(events.where((event) => event == 'dispose second'), isEmpty);
    expect(observations.last, 'second');

    owner.dispose();
    expect(events.where((event) => event == 'dispose component'), hasLength(1));
    expect(events.where((event) => event == 'dispose first'), hasLength(1));
    expect(events.where((event) => event == 'dispose second'), hasLength(1));
    expect(
      events.where((event) => event.startsWith('dispose adopted')),
      isEmpty,
    );
    expect(adopted.every((source) => !source.disposed), isTrue);
  });

  test(
    'proxy mount drains a pending R registration through ProviderScope',
    () async {
      final observations = <List<int>?>[];
      late _HostState slot;
      final owner = BuildOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _DerivedWatch(observations),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(observations, [null]);
      final registry = slot.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Derived), hasLength(1));

      slot.swap(
        () => Nest(
          children: [
            Provider<_Source1>.value(const _Source1(9)),
            ProxyProvider<_Source1, _Derived>(
              update: (_, value, previous) => _Derived([value.value]),
            ),
          ],
          child: const _Leaf(),
        ),
      );
      owner.flush();
      expect(registry.debugPendingOf(_Derived), isEmpty);
      expect(registry.debugNotifying, hasLength(1));
      expect(observations, [null]);

      await _pump();
      owner.flush();
      expect(observations, [null, null]);
      expect(registry.debugPendingOf(_Derived), hasLength(1));
    },
  );

  test('missing dependencies watch every type and withhold R', () {
    final observations = <List<int>?>[];
    final disposed = <_Derived>[];
    var updates = 0;
    late _HostState host;
    final owner = BuildOwner();

    owner.mountRoot(
      ProviderScope(
        child: _Host(
          onCreate: (state) => host = state,
          describe: () =>
              ProxyProvider6<
                _Source1,
                _Source2,
                _Source3,
                _Source4,
                _Source5,
                _Source6,
                _Derived
              >(
                create: (_) => _Derived(const [0]),
                update:
                    (
                      _,
                      value1,
                      value2,
                      value3,
                      value4,
                      value5,
                      value6,
                      previous,
                    ) {
                      updates++;
                      return _Derived(const []);
                    },
                dispose: disposed.add,
                child: _DerivedWatch(observations),
              ),
        ),
      ),
    );

    final registry = host.context.read<AvailabilityRegistry>()!;
    final pending = [
      registry.debugPendingOf(_Source1),
      registry.debugPendingOf(_Source2),
      registry.debugPendingOf(_Source3),
      registry.debugPendingOf(_Source4),
      registry.debugPendingOf(_Source5),
      registry.debugPendingOf(_Source6),
    ];
    expect(pending.every((bucket) => bucket.length == 1), isTrue);
    final proxyElement = pending.first.single;
    expect(
      pending.every((bucket) => identical(bucket.single, proxyElement)),
      isTrue,
    );
    expect(updates, 0);
    expect(observations, [null]);
    expect(registry.debugPendingOf(_Derived), hasLength(1));

    owner.dispose();
    expect(disposed, hasLength(1));
    expect(disposed.single.values, [0]);
  });
}
