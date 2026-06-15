import 'package:genesis_consent/genesis_consent.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

/// An interactive counter component for the console catalog.
///
/// Built entirely on `genesis_tree`'s composition layer — no perception
/// dependency. The configuration ([Counter]) is immutable; the live count
/// lives on [CounterState]; the dispatch seam ([Actionable]) lives on the
/// element ([CounterElement]), which forwards to its state. The state renders
/// the count as a `genesis_typesetting` [Text] (a render seed), so the counter
/// composes under a `Stage`/`Box` like any other render child.
class Counter extends StatefulSeed {
  /// Creates a counter labelled [label], counting from [start].
  const Counter({required this.label, this.start = 0, super.key});

  /// Display label shown beside the live count.
  final String label;

  /// The count at mount.
  final int start;

  @override
  CounterState createState() => CounterState();

  @override
  CounterElement createBranch() => CounterElement(this);
}

/// The actionable element for a [Counter]: it implements [Actionable] and
/// forwards to its [CounterState], so the consent router reaches the action
/// seam via `branch is Actionable` without touching the `@protected` state.
class CounterElement extends StatefulBranch implements Actionable {
  /// Creates the element for [seed].
  CounterElement(Counter super.seed);

  CounterState get _state => state as CounterState;

  @override
  void validateAction(String name, Map<String, Object?> payload) =>
      _state.validateAction(name, payload);

  @override
  ActionChange applyAction(String name, Map<String, Object?> payload) =>
      _state.applyAction(name, payload);
}

/// The live state for a [Counter]: holds the count, renders it, and honors the
/// `press` / `set` affordances declared in the catalog.
class CounterState extends State<Counter> {
  late int _count;

  /// The current live count. Exposed so callers can read live state directly.
  int get count => _count;

  @override
  void initState() {
    super.initState();
    _count = seed.start;
  }

  @override
  Seed build(TreeContext context) {
    // The child render seed is left UNKEYED: reusing the counter's own A2UI id
    // as a child key would mint a second branch answering to that id and the
    // consent hit-test would reject the action as ambiguous.
    return Text('${seed.label}: $_count');
  }

  /// Gate 3 (pure): rejects a malformed payload without mutating anything.
  void validateAction(String name, Map<String, Object?> payload) {
    switch (name) {
      case 'press':
        final amount = payload['amount'];
        if (amount != null && amount is! int) {
          throw const ActionPayloadException(
            '"amount" must be an integer when provided',
          );
        }
      case 'set':
        if (payload['value'] is! int) {
          throw const ActionPayloadException(
            '"value" is required and must be an integer',
          );
        }
      default:
        // The router only calls this for catalog-declared actions, so other
        // names never reach here; reject defensively without mutating.
        throw ActionPayloadException('counter does not afford "$name"');
    }
  }

  /// Enforce: applies the already-validated action through [setState], so the
  /// rebuild flows through the standard dirty/flush pipeline.
  ActionChange applyAction(String name, Map<String, Object?> payload) {
    final from = _count;
    switch (name) {
      case 'press':
        final amount = (payload['amount'] as int?) ?? 1;
        setState(() => _count += amount);
      case 'set':
        setState(() => _count = payload['value']! as int);
      default:
        throw StateError('unreachable: counter cannot apply "$name"');
    }
    return ActionChange(from: from, to: _count);
  }
}
