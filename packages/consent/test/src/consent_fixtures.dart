// Test fixtures for the consent action router.
//
// Per A22, expression-row tests consume genesis_perception's real Node/Field
// rather than inventing a vocabulary. The one thing perception does not ship
// is a *stateful, actionable* component, so this file adds [Counter] — a
// StatefulPerception whose [CounterState] implements genesis_consent's
// [Actionable] seam (the spike-5 CounterButton, productionized against the
// as-built packages). It is the target the enforce/reject hit-test acts on.
//
// consent_fixture.g.dart (generated) binds `counter` -> [Counter] here, and
// `node`/`field` -> the perception species.
import 'package:genesis_consent/genesis_consent.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Build-invocation counts keyed by counter label — the proof that ENFORCE
/// invalidates exactly the target subtree (ADR-0005 Decision 4). Reset per
/// test; incremented once per [CounterState.build].
final Map<String, int> consentFixtureBuildCounts = {};

/// A stateful integer counter leaf bound to catalog type `counter`.
///
/// A wire leaf (the catalog declares no children) that internally builds a
/// perception `Field` reflecting its live count — so the rendered projection
/// shows the count and a re-render is observable.
class Counter extends StatefulPerception {
  /// Creates a counter labelled [label], counting from [start].
  const Counter(this.label, {this.start = 0, super.key});

  /// Display label; also the build-count key.
  final String label;

  /// Initial count at mount.
  final int start;

  @override
  CounterState createState() => CounterState();
}

/// Live state for a [Counter]: holds the count, re-renders it as a `Field`,
/// and honors the `press` / `set` affordances through [Actionable].
class CounterState extends PerceptionState<Counter> implements Actionable {
  int _count = 0;

  /// The current live count. Exposed so tests can read live state directly.
  int get count => _count;

  @override
  void initState() {
    super.initState();
    _count = perception.start;
  }

  @override
  Seed build(PerceptionContext context) {
    consentFixtureBuildCounts.update(
      perception.label,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    // Render the live count as a perception leaf (A22 vocabulary).
    return Field(perception.label, '$_count');
  }

  // --- Actionable (ADR-0005 Decisions 2 gate 3 and 4) ---

  @override
  void validateAction(String name, Map<String, Object?> payload) {
    switch (name) {
      case 'press':
        final amount = payload['amount'];
        if (amount != null && amount is! int) {
          throw const ActionPayloadException(
            '"amount" must be an integer when present',
          );
        }
      case 'set':
        final value = payload['value'];
        if (value is! int) {
          throw const ActionPayloadException(
            '"value" is required and must be an integer',
          );
        }
      default:
        // Gate 2 guarantees only catalog-declared actions reach here.
        throw StateError('counter received undeclared action "$name"');
    }
  }

  @override
  ActionChange applyAction(String name, Map<String, Object?> payload) {
    final from = _count;
    switch (name) {
      case 'press':
        final amount = (payload['amount'] as int?) ?? 1;
        perceived(() => _count += amount);
      case 'set':
        final value = payload['value']! as int;
        perceived(() => _count = value);
      default:
        throw StateError('counter received undeclared action "$name"');
    }
    return ActionChange(from: from, to: _count);
  }
}
