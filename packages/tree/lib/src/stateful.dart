/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'buildable_element.dart';
import 'component.dart';
import 'build_context.dart';
import 'tree_lifecycle_phase.dart';
import 'build_owner.dart';

/// A [Component] whose element owns mutable [State] — the StatefulWidget analogue.
abstract class StatefulComponent extends Component {
  /// Creates a stateful component, optionally [key]ed.
  const StatefulComponent({super.key});

  /// Creates the mutable state for a element of this component.
  @factory
  State<StatefulComponent> createState();

  @override
  StatefulElement createElement() => StatefulElement(this);

  @override
  @Deprecated('Use createElement instead.')
  StatefulElement createBranch() => createElement();
}

/// Mutable state owned by a [StatefulElement], with the
/// initState/didChangeDependencies/build/dispose lifecycle.
abstract class State<T extends StatefulComponent> {
  /// The current [StatefulComponent] configuration of the owning element.
  T get component => _element!.component as T;

  /// Legacy spelling for [component].
  @Deprecated('Use component instead.')
  T get seed => component;

  /// The owning element's capability handle: a separate object, never
  /// the element itself; throws [StateError] when used after unmount.
  BuildContext get context {
    assert(_element != null, 'context accessed outside element lifecycle');
    return _element!.context;
  }

  StatefulElement? _element;

  /// Called exactly once, before the first build.
  ///
  /// Inherited lookups here must be dependency-free — use
  /// `context.getInheritedValueOfExactType<T>()`. Registering a dependency
  /// (`dependOnInheritedValueOfExactType`) asserts in debug mode: initState
  /// never re-runs, so the natural move of caching the returned value goes
  /// stale when the provider changes. Cache-and-track belongs in
  /// [didChangeDependencies], which re-runs on every change.
  @protected
  void initState() {}

  /// Called after [initState] and whenever a depended-on inherited value
  /// changes, before the next build.
  @protected
  void didChangeDependencies() {}

  /// Describes the child subtree for the current configuration and state.
  Component build(BuildContext context);

  /// Called when the owning element unmounts, before the subtree is released.
  @protected
  void dispose() {}

  /// The setState analogue: applies [fn], then marks the owning element as
  /// needing rebuild.
  void setState(VoidCallback fn) {
    fn();
    _element!.markNeedsRebuild();
  }
}

/// Mounted element for a [StatefulComponent]: creates and owns the [State], drives
/// its lifecycle, and delegates [build] to it.
class StatefulElement extends BuildableElement {
  /// Creates the element and its [State] for [component].
  StatefulElement(StatefulComponent component) : super(component) {
    _state = component.createState();
    _state._element = this;
  }

  late final State<StatefulComponent> _state;
  bool _firstBuild = true;
  bool _needsDidChangeDependencies = false;

  /// The mutable state owned by this element.
  ///
  /// `@protected`: only this element and its subclasses reach it (a domain
  /// element upgrades the return type; an actionable element forwards to it).
  /// It is **not** public API — external layers must not reach into a element's
  /// `State`. Tests that need it access it with an
  /// `invalid_use_of_protected_member` ignore.
  @protected
  State<StatefulComponent> get state => _state;

  @override
  Component build(BuildContext context) => _state.build(context);

  @override
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect}) {
    owner!.lifecyclePhaseGuard.checkCanDependOnInheritedValueOfExactType<T>();
    return super.dependOnInheritedValueOfExactType<T>(aspect: aspect);
  }

  @override
  void dependencyChanged() {
    _needsDidChangeDependencies = true;
    markNeedsRebuild();
  }

  @override
  void performRebuild() {
    final lifecyclePhaseGuard = owner!.lifecyclePhaseGuard;
    lifecyclePhaseGuard.runInPhase<void>(TreeLifecyclePhase.building, () {
      if (_firstBuild) {
        _firstBuild = false;
        lifecyclePhaseGuard.runInPhase<void>(
          TreeLifecyclePhase.initState,
          _state.initState,
        );
        _needsDidChangeDependencies = true;
      }
      if (_needsDidChangeDependencies) {
        _needsDidChangeDependencies = false;
        lifecyclePhaseGuard.runInPhase<void>(
          TreeLifecyclePhase.didChangeDependencies,
          _state.didChangeDependencies,
        );
      }
      super.performRebuild();
    });
  }

  @override
  void unmount() {
    owner!.lifecyclePhaseGuard.runInPhase<void>(
      TreeLifecyclePhase.dispose,
      _state.dispose,
    );
    super.unmount();
  }
}

/// Legacy name for [StatefulComponent].
@Deprecated('Use StatefulComponent instead.')
typedef StatefulSeed = StatefulComponent;

/// Legacy name for [StatefulElement].
@Deprecated('Use StatefulElement instead.')
typedef StatefulBranch = StatefulElement;
