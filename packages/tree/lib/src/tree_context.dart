import 'package:meta/meta.dart';

import 'branch.dart';

/// Build-time capability handle into the tree — the BuildContext analogue
/// minus the Element≡BuildContext "original sin".
///
/// A [Branch] never implements this interface. The handle is a distinct
/// object bound to a branch; once that branch unmounts, every member except
/// [mounted] throws [StateError]. Holding a handle across an async gap is
/// expected (agents do it routinely) — the protection is executable, not a
/// lint: probe [mounted] after the gap before using the handle.
abstract class TreeContext {
  /// Whether the bound branch is still mounted. Never throws — this is the
  /// safe staleness probe for handles held across async gaps.
  bool get mounted;

  /// The key of the bound branch's `Seed` config, or null if unkeyed.
  ///
  /// Throws [StateError] after the bound branch unmounts.
  Object? get key;

  /// Stable id of the bound branch, issued by `TreeOwner.issueId` at mount.
  ///
  /// Throws [StateError] after the bound branch unmounts.
  String get branchId;

  /// Returns the nearest ancestor value provided via `InheritedSeed<T>` of
  /// exact type [T], registering the bound branch as a dependent; null when
  /// no such ancestor exists.
  ///
  /// Throws [StateError] after the bound branch unmounts.
  T? dependOnInheritedSeedOfExactType<T extends Object>();

  /// Marks the bound branch dirty for the next `TreeOwner.flush`.
  ///
  /// Throws [StateError] after the bound branch unmounts.
  void markNeedsRebuild();
}

/// Creates the canonical [TreeContext] handle bound to [branch].
///
/// Package-internal: code obtains a branch's handle via [Branch.context].
@internal
TreeContext createTreeContext(Branch branch) => _BranchContext(branch);

/// The private handle implementation: delegates to the bound [Branch]
/// and asserts validity on every use — the async-gap protection, executable.
class _BranchContext implements TreeContext {
  _BranchContext(this._branch);

  final Branch _branch;

  void _checkMounted(String member) {
    if (!_branch.mounted) {
      throw StateError(
        'TreeContext.$member used after its branch unmounted (async-gap '
        'protection). Probe TreeContext.mounted after an async gap before '
        'using the handle.',
      );
    }
  }

  @override
  bool get mounted => _branch.mounted;

  @override
  Object? get key {
    _checkMounted('key');
    return _branch.key;
  }

  @override
  String get branchId {
    _checkMounted('branchId');
    return _branch.branchId;
  }

  @override
  T? dependOnInheritedSeedOfExactType<T extends Object>() {
    _checkMounted('dependOnInheritedSeedOfExactType');
    return _branch.dependOnInheritedSeedOfExactType<T>();
  }

  @override
  void markNeedsRebuild() {
    _checkMounted('markNeedsRebuild');
    _branch.markNeedsRebuild();
  }
}
