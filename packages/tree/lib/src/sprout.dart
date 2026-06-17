/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
///
/// `Sprout` is the hooks-style stateful primitive — one class, one [build],
/// state declared inline. It removes the `StatefulSeed` + separate `State<T>`
/// ceremony for the common case while keeping `State<T>` available for complex
/// lifecycles (additive, not a replacement). The `Sprout` subclass is still the
/// reconciliation type-tag (`Seed.canUpdate` keys on `runtimeType`); state lives
/// on the persistent [SproutBranch] and is reached only through the [SproutContext]
/// handle — never the branch itself.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'component_branch.dart';
import 'key.dart';
import 'seed.dart';
import 'tree_context.dart';

/// A cleanup callback returned by a [SproutContext.useEffect] effect, run before
/// the effect re-runs and on unmount.
typedef Dispose = void Function();

/// A [Seed] whose branch holds its state in hooks declared inline in [build] —
/// the hooks-style alternative to `StatefulSeed` + `State<T>`.
///
/// Subclass it and override [build], calling `context.useState` / `useStream` /
/// `useEffect` / `useMemo` to declare state. The subclass type is the reconcile
/// tag, so two `Sprout`s of different subclasses never update into one another;
/// state persists on the branch across config updates, keyed by call order.
abstract class Sprout extends Seed {
  /// Creates a sprout, optionally [key]ed.
  const Sprout({super.key});

  /// Describes the child subtree, reading state inline via [context] hooks.
  ///
  /// Re-runs on mount and on every config update. Hooks must be called
  /// unconditionally and in the same order every build (the rules of hooks).
  /// A changed hook count or a type change at a position throws; a same-shape
  /// reorder (same count and types) cannot be detected, so keep call order
  /// stable.
  @protected
  Seed build(SproutContext context);

  @override
  SproutBranch createBranch() => SproutBranch(this);
}

/// A mutable state cell returned by [SproutContext.useState]. Setting [value]
/// marks the owning branch for rebuild (the `setState` analogue).
class StateCell<T> {
  StateCell._(this._value, this._branch);

  T _value;
  final SproutBranch _branch;

  /// The current value.
  T get value => _value;

  /// Sets the value and marks the owning branch for rebuild. Always schedules
  /// a rebuild (no equality gate), matching `State.setState`. A no-op once the
  /// branch has unmounted (`markNeedsRebuild` guards on `mounted` — the same
  /// post-unmount silence as `setState`, deliberately *not* the context
  /// handle's throw, since a late async callback should not crash).
  set value(T next) {
    assert(
      !_branch._debugInBuild,
      'StateCell.value set during Sprout.build — set state from an event '
      'handler or effect, never during build (it would loop the rebuild).',
    );
    _value = next;
    _branch.markNeedsRebuild();
  }

  /// Functional update: applies [update] to the current value, then [value]=.
  /// Prefer this in async handlers to avoid read-modify-write races.
  void set(T Function(T previous) update) => value = update(_value);
}

/// The build-time hook-dispatch handle passed to [Sprout.build].
///
/// Extends [TreeContext] (throw-after-unmount inherited) with the hook
/// surface. Hooks may only be called inside [Sprout.build], unconditionally and
/// in a stable order. A changed hook count or a type change at a position
/// throws; a call outside build asserts; a same-shape reorder is undetectable
/// (the positional-hooks caveat) — keep the order stable.
abstract class SproutContext implements TreeContext {
  /// Declares a persistent state [StateCell] seeded with [initial] on first build;
  /// later builds return the same cell (the new [initial] is ignored).
  StateCell<T> useState<T>(T initial);

  /// Subscribes to [source] and returns its latest value (or [initial] before
  /// the first event). Re-subscribes only when the source changes (by `==`,
  /// keeping the last value); cancels on unmount. Collapses `Watch`.
  T useStream<T>(Stream<T> source, {required T initial});

  /// Runs [effect] as a microtask-deferred passive effect. With [keys] omitted
  /// it runs after every build; `const []` runs once (mount); a non-empty list
  /// re-runs when the keys change element-wise. [effect] may return a [Dispose]
  /// cleanup, run before the next re-run and on unmount.
  void useEffect(Dispose? Function() effect, [List<Object?>? keys]);

  /// Returns a value computed by [create], recomputed only when [keys] change.
  /// Stabilizes derived identities (e.g. a stream) across rebuilds.
  T useMemo<T>(T Function() create, List<Object?> keys);
}

/// Mounted branch for a [Sprout]: a [ComponentBranch] that owns the persistent
/// hook slots and dispatches hooks by call order.
class SproutBranch extends ComponentBranch {
  /// Creates the branch for [seed].
  SproutBranch(Sprout super.seed);

  final List<_HookState> _hooks = [];
  int _cursor = 0;
  bool _firstBuild = true;
  bool _debugInBuild = false;
  List<_EffectHook>? _pendingEffects;
  late final SproutContext _sproutContext = _createSproutContext(this);

  @override
  Seed build(TreeContext context) {
    _cursor = 0;
    assert(() {
      _debugInBuild = true;
      return true;
    }());
    final child = (seed as Sprout).build(_sproutContext);
    assert(() {
      _debugInBuild = false;
      return true;
    }());
    // Under-count (fewer hooks than registered) would silently misbind slots
    // on the next build, so it throws always — over-count and type drift
    // already throw in _slotAt.
    if (_cursor != _hooks.length) {
      throw StateError(
        'Sprout.build called $_cursor hooks but ${_hooks.length} are '
        'registered — hooks must be called unconditionally and in the same '
        'order every build (no conditional or early-returned hooks).',
      );
    }
    _firstBuild = false;
    return child;
  }

  @override
  void performRebuild() {
    super.performRebuild(); // build() fills _pendingEffects; child reconciles.
    _scheduleEffects();
  }

  @override
  void unmount() {
    // Reverse-order teardown (React convention): later hooks may depend on
    // earlier ones. Each dispose is guarded so one throwing user cleanup can't
    // strand a sibling's stream cancel or break the tree teardown; the first
    // error is rethrown after every teardown has run and the branch unmounts.
    Object? firstError;
    StackTrace? firstStack;
    for (var i = _hooks.length - 1; i >= 0; i--) {
      try {
        _hooks[i].dispose();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    _pendingEffects = null;
    super.unmount();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  // --- hook dispatch (private; reached via _SproutContext, same library) ---

  StateCell<T> _useState<T>(T initial) {
    assert(_debugInBuild, _outsideBuildMessage('useState'));
    if (_firstBuild) {
      final cell = StateCell<T>._(initial, this);
      _hooks.add(_StateHook<T>(cell));
      _cursor++;
      return cell;
    }
    return _slotAt<_StateHook<T>>(_cursor++).cell;
  }

  T _useStream<T>(Stream<T> source, T initial) {
    assert(_debugInBuild, _outsideBuildMessage('useStream'));
    if (_firstBuild) {
      final hook = _StreamHook<T>(source, initial);
      hook.subscription = source.listen((event) {
        hook.value = event;
        markNeedsRebuild();
      });
      _hooks.add(hook);
      _cursor++;
      return hook.value;
    }
    final hook = _slotAt<_StreamHook<T>>(_cursor++);
    // Compare by `==`, not `identical`: `StreamController.stream` returns a new
    // wrapper each access but compares equal for the same controller, so `==`
    // correctly treats "the same stream" as unchanged. Derived streams (map,
    // where) compare unequal each build — memoize them via useMemo to keep one
    // subscription.
    if (hook.source != source) {
      unawaited(hook.subscription.cancel());
      hook.source = source;
      hook.subscription = source.listen((event) {
        hook.value = event;
        markNeedsRebuild();
      });
      // Keep the last value across the swap; the new stream's first event wins.
    }
    return hook.value;
  }

  void _useEffect(Dispose? Function() effect, List<Object?>? keys) {
    assert(_debugInBuild, _outsideBuildMessage('useEffect'));
    if (_firstBuild) {
      final hook = _EffectHook(keys)..pendingEffect = effect;
      _hooks.add(hook);
      _cursor++;
      (_pendingEffects ??= []).add(hook);
      return;
    }
    final hook = _slotAt<_EffectHook>(_cursor++);
    final shouldRun = keys == null || !_keysEqual(hook.keys, keys);
    hook.keys = keys;
    if (shouldRun) {
      hook.pendingEffect = effect;
      (_pendingEffects ??= []).add(hook);
    }
  }

  T _useMemo<T>(T Function() create, List<Object?> keys) {
    assert(_debugInBuild, _outsideBuildMessage('useMemo'));
    if (_firstBuild) {
      final value = create();
      _hooks.add(_MemoHook<T>(value, keys));
      _cursor++;
      return value;
    }
    final hook = _slotAt<_MemoHook<T>>(_cursor++);
    if (!_keysEqual(hook.keys, keys)) {
      hook.value = create();
      hook.keys = keys;
    }
    return hook.value;
  }

  /// Reuses the slot at [index], enforcing the rules of hooks: a higher index
  /// than registered (more hooks this build) or a type mismatch (different
  /// order) throws — always on, since both would otherwise corrupt state.
  T _slotAt<T extends _HookState>(int index) {
    if (index >= _hooks.length) {
      throw StateError(
        'Sprout called more hooks this build than last (at position $index of '
        '${_hooks.length}) — hooks must be called unconditionally and in the '
        'same order every build.',
      );
    }
    final slot = _hooks[index];
    if (slot is! T) {
      throw StateError(
        'Sprout hook order changed: position $index was ${slot.runtimeType} '
        'last build but $T this build — hooks must be called in the same order '
        'every build (no conditional hooks).',
      );
    }
    return slot;
  }

  void _scheduleEffects() {
    final pending = _pendingEffects;
    if (pending == null || pending.isEmpty) return;
    _pendingEffects = null;
    // Passive effects run after the flush pass unwinds (microtask), so an
    // effect's markNeedsRebuild lands in a fresh dirty set and cannot trip
    // TreeOwner's "re-dirtied after built this pass" assert.
    scheduleMicrotask(() {
      // Skip if unmounted before the microtask drained (teardown already ran).
      if (!mounted) return;
      // Two-phase (React order): run ALL previous cleanups, then ALL effects,
      // so a cleanup that releases a resource runs before any effect that
      // re-acquires it.
      for (final hook in pending) {
        if (hook.pendingEffect == null) continue;
        hook.cleanup?.call();
        hook.cleanup = null;
      }
      for (final hook in pending) {
        final effect = hook.pendingEffect;
        if (effect == null) continue;
        hook.pendingEffect = null;
        hook.cleanup = effect();
      }
    });
  }

  static String _outsideBuildMessage(String hook) =>
      '$hook called outside Sprout.build(). Hooks may only be called inside '
      'build (capturing the SproutContext and calling a hook later is a rules-'
      'of-hooks violation).';
}

bool _keysEqual(List<Object?>? a, List<Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Creates the SproutContext handle bound to [branch] (wraps the canonical
// TreeContext). Private: build receives it lazily via the branch.
SproutContext _createSproutContext(SproutBranch branch) =>
    _SproutContext(branch);

class _SproutContext implements SproutContext {
  _SproutContext(this._branch) : _delegate = _branch.context;

  final SproutBranch _branch;
  final TreeContext _delegate;

  // TreeContext surface — delegated so throw-after-unmount is inherited.
  @override
  bool get mounted => _delegate.mounted;

  @override
  Key? get key => _delegate.key;

  @override
  String get branchId => _delegate.branchId;

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>() =>
      _delegate.dependOnInheritedSeedOfExactType<T>();

  @override
  void markNeedsRebuild() => _delegate.markNeedsRebuild();

  // Hook surface — forwarded to the branch's private dispatch.
  @override
  StateCell<T> useState<T>(T initial) => _branch._useState(initial);

  @override
  T useStream<T>(Stream<T> source, {required T initial}) =>
      _branch._useStream(source, initial);

  @override
  void useEffect(Dispose? Function() effect, [List<Object?>? keys]) =>
      _branch._useEffect(effect, keys);

  @override
  T useMemo<T>(T Function() create, List<Object?> keys) =>
      _branch._useMemo(create, keys);
}

// --- hook slots ------------------------------------------------------------

sealed class _HookState {
  void dispose() {}
}

final class _StateHook<T> extends _HookState {
  _StateHook(this.cell);
  final StateCell<T> cell;
}

final class _StreamHook<T> extends _HookState {
  _StreamHook(this.source, this.value);
  Stream<T> source;
  T value;
  late StreamSubscription<T> subscription;

  @override
  void dispose() => unawaited(subscription.cancel());
}

final class _EffectHook extends _HookState {
  _EffectHook(this.keys);
  List<Object?>? keys;
  Dispose? cleanup;
  Dispose? Function()? pendingEffect;

  @override
  void dispose() => cleanup?.call();
}

final class _MemoHook<T> extends _HookState {
  _MemoHook(this.value, this.keys);
  T value;
  List<Object?> keys;
}
