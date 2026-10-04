/// Marks a class whose instances are derived, never constructed bare.
///
/// A value that composes down a tree — a service bundle, a posture, an
/// environment — is built inside its own library and reached everywhere else
/// through a `derive` or `copyWith` on the ambient value, so a field set
/// above is never silently dropped below. `genesis_lint`'s
/// `derive_dont_construct` rejects a constructor call of an annotated class
/// from any other library.
///
/// Use the [deriveOnly] constant rather than constructing this class.
final class DeriveOnly {
  /// Creates the marker; prefer the [deriveOnly] constant.
  const DeriveOnly();
}

/// Marks a class as constructed only inside its own library.
const deriveOnly = DeriveOnly();

/// Marks a method or function that performs an effect: it starts, changes or
/// stops something outside the tree, such as a process, a write or a
/// delivery.
///
/// `genesis_lint`'s `effects_only_in_leaves` rejects an invocation of an
/// annotated member outside an [EffectLeafMarker] class. The class name
/// leaves `Effect` free for a consumer's own effect types.
///
/// Use the [effect] constant rather than constructing this class.
final class EffectMarker {
  /// Creates the marker; prefer the [effect] constant.
  const EffectMarker();
}

/// Marks a method or function that performs an effect.
const effect = EffectMarker();

/// Marks a class that owns effects through its lifecycle — typically the
/// Element of a leaf Component, which starts or adopts its artifact, updates
/// it, and disposes it.
///
/// Subclasses inherit the mark. `genesis_lint`'s `effects_only_in_leaves`
/// accepts [effect] invocations inside such a class, outside its build. The
/// class name leaves `EffectLeaf` free for a consumer's own leaf types.
///
/// Use the [effectLeaf] constant rather than constructing this class.
final class EffectLeafMarker {
  /// Creates the marker; prefer the [effectLeaf] constant.
  const EffectLeafMarker();
}

/// Marks a class that owns effects through its lifecycle.
const effectLeaf = EffectLeafMarker();
