import 'package:genesis_tree/genesis_tree.dart';

/// Owns the root element, holds the dirty set, and drives synchronous
/// depth-ordered harvest flushes — `PerceptionOwner` builds on [BuildOwner]
/// by extension.
///
/// The scheduler mechanics (dirty set, depth-ordered drain, the
/// empty→non-empty callback edge, id issuance) are all inherited; this class
/// adds the measurement domain's names for them. A `PerceptionOwner` is
/// usable anywhere a [BuildOwner] is expected.
class PerceptionOwner extends BuildOwner {
  /// Domain alias of [BuildOwner.onNeedsFlush]: fires exactly once on the
  /// empty→non-empty edge of the dirty set, and again only after a
  /// [flushHarvest] drains it.
  VoidCallback? get onNeedsHarvest => onNeedsFlush;
  set onNeedsHarvest(VoidCallback? callback) => onNeedsFlush = callback;

  /// Domain alias of [BuildOwner.flush]: drains the dirty set in depth order
  /// and returns the elements this call actually rebuilt, in flush order —
  /// the drained dirty set exposed to harvest backends.
  List<Element> flushHarvest() => flush();
}
