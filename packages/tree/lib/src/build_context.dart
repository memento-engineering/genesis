import 'package:meta/meta.dart';

import 'element.dart';
import 'key.dart';

/// Build-time capability handle into the tree — the BuildContext analogue
/// minus the Element≡BuildContext "original sin".
///
/// A [Element] never implements this interface. The handle is a distinct
/// object bound to a element; once that element unmounts, every member except
/// [mounted] throws [StateError]. Holding a handle across an async gap is
/// expected (agents do it routinely) — the protection is executable, not a
/// lint: probe [mounted] after the gap before using the handle.
abstract class BuildContext {
  /// Whether the bound element is still mounted. Never throws — this is the
  /// safe staleness probe for handles held across async gaps.
  bool get mounted;

  /// The [Key] of the bound element's `Component` config, or null if unkeyed.
  ///
  /// Throws [StateError] after the bound element unmounts.
  Key? get key;

  /// Stable id of the bound element, issued by `BuildOwner.issueId` at mount.
  ///
  /// Throws [StateError] after the bound element unmounts.
  String get elementId;

  /// Legacy spelling for [elementId].
  @Deprecated('Use elementId instead.')
  String get branchId;

  /// Returns the nearest ancestor value provided via `InheritedComponent<T>` of
  /// exact type [T], registering the bound element as a dependent; null when
  /// no such ancestor exists.
  ///
  /// Pass [aspect] to scope the dependency to one aspect of an
  /// `InheritedModel<T, A>` provider; omitting it depends on the whole
  /// value. A non-null [aspect] against a plain `InheritedComponent` provider
  /// throws [ArgumentError].
  ///
  /// Throws [StateError] after the bound element unmounts.
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect});

  /// Legacy spelling for [dependOnInheritedValueOfExactType].
  @Deprecated('Use dependOnInheritedValueOfExactType instead.')
  T? dependOnInheritedSeedOfExactType<T extends Object>({Object? aspect});

  /// Returns the nearest ancestor value provided via `InheritedComponent<T>` of
  /// exact type [T] **without registering a dependency**; null when no such
  /// ancestor exists.
  ///
  /// The non-subscribing counterpart of [dependOnInheritedValueOfExactType]:
  /// the returned value is a snapshot — a later change to the provided value
  /// does not rebuild the bound element. This is the lookup to use from
  /// `State.initState` (which never re-runs, so a subscription registered
  /// there invites a stale cached read) and from effects and teardown; use
  /// the depend variant wherever the element must rebuild on change.
  ///
  /// Throws [StateError] after the bound element unmounts.
  T? getInheritedValueOfExactType<T extends Object>();

  /// Legacy spelling for [getInheritedValueOfExactType].
  @Deprecated('Use getInheritedValueOfExactType instead.')
  T? getInheritedSeedOfExactType<T extends Object>();

  /// Marks the bound element dirty for the next `BuildOwner.flush`.
  ///
  /// Throws [StateError] after the bound element unmounts.
  void markNeedsRebuild();
}

/// Creates the canonical [BuildContext] handle bound to [element].
///
/// Package-internal: code obtains a element's handle via [Element.context].
@internal
BuildContext createBuildContext(Element element) => _ElementContext(element);

/// Legacy spelling for [createBuildContext].
@Deprecated('Use createBuildContext instead.')
BuildContext createTreeContext(Element element) => createBuildContext(element);

/// The private handle implementation: delegates to the bound [Element]
/// and asserts validity on every use — the async-gap protection, executable.
class _ElementContext implements BuildContext {
  _ElementContext(this._element);

  final Element _element;

  void _checkMounted(String member) {
    if (!_element.mounted) {
      throw StateError(
        'BuildContext.$member used after its element unmounted (async-gap '
        'protection). Probe BuildContext.mounted after an async gap before '
        'using the handle.',
      );
    }
  }

  @override
  bool get mounted => _element.mounted;

  @override
  Key? get key {
    _checkMounted('key');
    return _element.key;
  }

  @override
  String get elementId {
    _checkMounted('elementId');
    return _element.elementId;
  }

  @override
  String get branchId => elementId;

  @override
  T? dependOnInheritedValueOfExactType<T extends Object>({Object? aspect}) {
    _checkMounted('dependOnInheritedValueOfExactType');
    return _element.dependOnInheritedValueOfExactType<T>(aspect: aspect);
  }

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>({Object? aspect}) {
    return dependOnInheritedValueOfExactType<T>(aspect: aspect);
  }

  @override
  T? getInheritedValueOfExactType<T extends Object>() {
    _checkMounted('getInheritedValueOfExactType');
    return _element.getInheritedValueOfExactType<T>();
  }

  @override
  T? getInheritedSeedOfExactType<T extends Object>() {
    return getInheritedValueOfExactType<T>();
  }

  @override
  void markNeedsRebuild() {
    _checkMounted('markNeedsRebuild');
    _element.markNeedsRebuild();
  }
}

/// Legacy name for [BuildContext].
@Deprecated('Use BuildContext instead.')
typedef TreeContext = BuildContext;
