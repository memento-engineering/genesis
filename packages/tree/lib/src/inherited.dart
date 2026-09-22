/// EXPERIMENTAL: this API may change before 1.0; it freezes only after a
/// second consumer beyond perception adopts it.
library;

import 'package:meta/meta.dart';

import 'element.dart';
import 'component.dart';

/// Provides an ambient value of type [T] to all descendants in the tree —
/// the InheritedWidget analogue.
///
/// Usage:
///   `InheritedComponent<String>(value: 'hello', child: MyComponent())`
///
/// Descendants subscribe with
///   `context.dependOnInheritedValueOfExactType<String>()`
/// or take a dependency-free snapshot with
///   `context.getInheritedValueOfExactType<String>()`.
///
/// Every dependent of an `InheritedComponent` is invalidated whenever
/// [updateShouldNotify] is true. When dependents care about DIFFERENT parts
/// of one value and should not rebuild for each other's changes, use
/// [InheritedModel] instead: it scopes each dependency to an aspect.
class InheritedComponent<T extends Object> extends Component {
  /// Creates a provider of [value] over [child].
  const InheritedComponent({
    required this.value,
    required this.child,
    super.key,
  });

  /// The provided value.
  final T value;

  /// The subtree within which [value] is visible.
  final Component child;

  /// Returns true when [oldComponent]'s value differs from the new [value].
  /// Subclasses may override for custom equality.
  bool updateShouldNotify(InheritedComponent<T> oldComponent) =>
      value != oldComponent.value;

  @override
  InheritedElement<T> createElement() => InheritedElement<T>(this);

  @override
  @Deprecated('Use createElement instead.')
  InheritedElement<T> createBranch() => createElement();
}

/// Mounted element for [InheritedComponent]. Owns the dependent set, reconciles the
/// single child via the rebuild hook, and invalidates dependents through
/// [Element.dependencyChanged] when the value changes.
class InheritedElement<T extends Object> extends InheritedElementBase {
  /// Creates the element for [component].
  InheritedElement(InheritedComponent<T> super.component);

  final Set<Element> _dependents = {};
  Element? _child;

  InheritedComponent<T> get _typed => component as InheritedComponent<T>;

  /// The currently provided value.
  T get value => _typed.value;

  // --- InheritedElementBase ---

  @override
  U? getValueAs<U extends Object>() => T == U ? value as U : null;

  @override
  void addDependent(Element element, {Object? aspect}) {
    if (aspect != null) {
      throw ArgumentError.value(
        aspect,
        'aspect',
        'InheritedComponent<$T> provides no aspects — an aspect-scoped '
            'dependency needs an InheritedModel<$T, A> provider. Depend '
            'without an aspect, or provide the value with an InheritedModel.',
      );
    }
    _dependents.add(element);
  }

  @override
  void removeDependent(Element element) {
    if (_dependents.remove(element)) {
      element.removeDependency(this);
    }
  }

  /// Dependents registered via dependOnInheritedValueOfExactType.
  /// Exposed for testing. Do not use in production code.
  Set<Element> get dependents => _dependents;

  /// The mounted child element. Exposed for testing.
  /// Do not use in production code.
  Element? get childElement => _child;

  /// Legacy spelling for [childElement].
  @Deprecated('Use childElement instead.')
  Element? get childBranch => childElement;

  // --- Lifecycle ---

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  /// The rebuild hook of an inherited element: reconcile the single child
  /// against the current component's child config.
  @override
  void performRebuild() {
    _child = updateChild(_child, _typed.child, 0);
  }

  @override
  void update(Component newComponent) {
    assert(
      Component.canUpdate(component, newComponent),
      'update() called with a Component that fails canUpdate; '
      'use unmount() + mount() for type/key changes.',
    );
    final old = _typed;
    // Flutter ProxyElement order: notify dependents BEFORE the base update
    // invokes the rebuild hook. A dependent inside the
    // child subtree is then force-rebuilt exactly once during reconciliation
    // (clearing its dirty flag) instead of rebuilding a second time when the
    // owner drains the dirty set.
    notifyDependents(old, newComponent as InheritedComponent<T>);
    super.update(newComponent);
  }

  /// Invalidates dependents affected by [oldComponent] → [newComponent].
  ///
  /// The base rule is InheritedWidget's: when
  /// [InheritedComponent.updateShouldNotify] is true, EVERY dependent is
  /// invalidated. [InheritedModelElement] overrides this to consult each
  /// dependent's recorded aspects.
  @protected
  void notifyDependents(
    InheritedComponent<T> oldComponent,
    InheritedComponent<T> newComponent,
  ) {
    if (!newComponent.updateShouldNotify(oldComponent)) return;
    for (final dep in List.of(_dependents)) {
      dep.dependencyChanged();
    }
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void unmount() {
    for (final dep in List.of(_dependents)) {
      dep.removeDependency(this);
    }
    _dependents.clear();
    _child = updateChild(_child, null, 0);
    super.unmount();
  }
}

/// Provides an ambient value of type [T] whose dependents may subscribe to a
/// single ASPECT of it — the InheritedModel analogue.
///
/// A dependent subscribes with
///   `context.dependOnInheritedValueOfExactType<T>(aspect: someAspect)`
/// and is invalidated only when [updateShouldNotifyDependent] reports the
/// change as affecting one of the aspects it asked for. A dependent that
/// omits the aspect depends on the whole value, exactly as under
/// [InheritedComponent].
///
/// Lookup is unchanged — the parent walk still matches the nearest provider
/// of exact value-type [T] — so a plain
/// `dependOnInheritedValueOfExactType<T>()` finds an
/// `InheritedModel<T, A>` too and gets a whole-value dependency.
///
/// The house shape for a consumer is its own static `of`:
///
/// ```dart
/// static Environment? of(BuildContext context, {Lane? aspect}) =>
///     context.dependOnInheritedValueOfExactType<Environment>(aspect: aspect);
/// ```
class InheritedModel<T extends Object, A extends Object>
    extends InheritedComponent<T> {
  /// Creates an aspect-scoped provider of [value] over [child].
  const InheritedModel({required super.value, required super.child, super.key});

  /// Whether a dependent that subscribed to [dependencies] must rebuild now
  /// that this component has replaced [oldComponent].
  ///
  /// Called once per aspect-scoped dependent, and only after
  /// [InheritedComponent.updateShouldNotify] already returned true — so the
  /// default (`true`) makes a subclass that ignores aspects behave exactly
  /// like an [InheritedComponent]. [dependencies] is never empty: a dependent that
  /// asked for no aspect depends on the whole value and is invalidated
  /// without consulting this hook.
  bool updateShouldNotifyDependent(
    covariant InheritedModel<T, A> oldComponent,
    Set<A> dependencies,
  ) => true;

  @override
  InheritedModelElement<T, A> createElement() =>
      InheritedModelElement<T, A>(this);

  @override
  @Deprecated('Use createElement instead.')
  InheritedModelElement<T, A> createBranch() => createElement();
}

/// Mounted element for [InheritedModel]: [InheritedElement] plus
/// per-dependent aspect bookkeeping. [notifyDependents] consults
/// [InheritedModel.updateShouldNotifyDependent] with the aspects each
/// dependent asked for and invalidates only those it reports as affected.
///
/// Recorded limitation (it matches the plain provider): a dependency is
/// recorded at lookup and cleared only by [removeDependent] or unmount — the
/// spine never resets dependencies between rebuilds. A element that asks for
/// different aspects across successive builds therefore ACCUMULATES them and
/// is over-notified, never under-notified. Narrowing would need a per-build
/// dependency reset on `Element`, which the spine deliberately does not have.
class InheritedModelElement<T extends Object, A extends Object>
    extends InheritedElement<T> {
  /// Creates the element for [component].
  InheritedModelElement(InheritedModel<T, A> super.component);

  // Per-dependent aspect subscriptions. An EMPTY set means "the whole value"
  // (the dependent asked without an aspect); it is sticky, so a later
  // aspect-scoped lookup by the same element cannot narrow a whole-value
  // dependency.
  final Map<Element, Set<A>> _aspects = {};

  /// The aspects [element] subscribed to, or null when it is not a dependent;
  /// an empty set means a whole-value dependency. Exposed for testing.
  /// Do not use in production code.
  Set<A>? aspectsOf(Element element) => _aspects[element];

  @override
  void addDependent(Element element, {Object? aspect}) {
    if (aspect != null && aspect is! A) {
      throw ArgumentError.value(
        aspect,
        'aspect',
        'InheritedModel<$T, $A> scopes dependencies by $A; got a '
            '${aspect.runtimeType}. Pass an aspect of type $A, or none to depend '
            'on the whole value.',
      );
    }
    super.addDependent(element);
    final existing = _aspects[element];
    if (existing != null && existing.isEmpty) return; // whole-value is sticky
    if (aspect == null) {
      _aspects[element] = <A>{};
      return;
    }
    (_aspects[element] ??= <A>{}).add(aspect as A);
  }

  @override
  void removeDependent(Element element) {
    _aspects.remove(element);
    super.removeDependent(element);
  }

  @override
  void notifyDependents(
    InheritedComponent<T> oldComponent,
    InheritedComponent<T> newComponent,
  ) {
    final newModel = newComponent as InheritedModel<T, A>;
    final oldModel = oldComponent as InheritedModel<T, A>;
    if (!newModel.updateShouldNotify(oldModel)) return;
    for (final dep in List.of(_dependents)) {
      final aspects = _aspects[dep];
      if (aspects == null ||
          aspects.isEmpty ||
          newModel.updateShouldNotifyDependent(oldModel, aspects)) {
        dep.dependencyChanged();
      }
    }
  }

  @override
  void unmount() {
    super.unmount();
    _aspects.clear();
  }
}

/// Legacy name for [InheritedComponent].
@Deprecated('Use InheritedComponent instead.')
typedef InheritedSeed<T extends Object> = InheritedComponent<T>;

/// Legacy name for [InheritedElement].
@Deprecated('Use InheritedElement instead.')
typedef InheritedBranch<T extends Object> = InheritedElement<T>;

/// Legacy name for [InheritedModel].
@Deprecated('Use InheritedModel instead.')
typedef InheritedModelSeed<T extends Object, A extends Object> =
    InheritedModel<T, A>;

/// Legacy name for [InheritedModelElement].
@Deprecated('Use InheritedModelElement instead.')
typedef InheritedModelBranch<T extends Object, A extends Object> =
    InheritedModelElement<T, A>;
