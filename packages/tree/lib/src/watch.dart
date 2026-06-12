/// EXPERIMENTAL — two-consumer rule (ADR-0001): this API freezes only after
/// perception and one expression surface both consume it.
library;

import 'dart:async';

import 'seed.dart';
import 'stateful.dart';
import 'tree_context.dart';

/// Subscribes to [source] and rebuilds with each event — the Attention
/// primitive (register A13: Watch lives in tree's composition layer; it is
/// pure composition + dart:async with zero domain semantics).
class Watch<T> extends StatefulSeed {
  /// Creates a watcher over [source], building via [builder], starting from
  /// [initialValue] until the first event arrives.
  const Watch(
    this.source,
    this.builder, {
    required this.initialValue,
    super.key,
  });

  /// The stream of values to watch.
  final Stream<T> source;

  /// Builds the child subtree for the latest value.
  final Seed Function(T value) builder;

  /// The value used before [source] first emits.
  final T initialValue;

  @override
  WatchState<T> createState() => WatchState<T>();
}

/// State for [Watch]: holds the latest value and the stream subscription;
/// each event flows through the setState analogue into a rebuild.
class WatchState<T> extends State<Watch<T>> {
  late T _value;
  StreamSubscription<T>? _subscription;

  @override
  void initState() {
    _value = seed.initialValue;
    _subscription = seed.source.listen((event) {
      setState(() => _value = event);
    });
  }

  @override
  Seed build(TreeContext context) => seed.builder(_value);

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
