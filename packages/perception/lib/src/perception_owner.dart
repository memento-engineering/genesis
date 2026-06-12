import 'package:genesis_tree/genesis_tree.dart';

/// Owns the root element, holds the dirty set, and drives synchronous
/// depth-ordered harvest flushes — `PerceptionOwner` builds on [TreeOwner]
/// by extension (genesis ADR-0001 Decision 6 / A12).
///
/// The scheduler mechanics (dirty set, depth-ordered drain, the
/// empty→non-empty callback edge, id issuance) are all inherited; this class
/// adds the measurement domain's names for them. A `PerceptionOwner` is
/// usable anywhere a [TreeOwner] is expected.
class PerceptionOwner extends TreeOwner {
  /// Domain alias of [TreeOwner.onNeedsFlush]: fires exactly once on the
  /// empty→non-empty edge of the dirty set, and again only after a
  /// [flushHarvest] drains it.
  VoidCallback? get onNeedsHarvest => onNeedsFlush;
  set onNeedsHarvest(VoidCallback? callback) => onNeedsFlush = callback;

  /// Domain alias of [TreeOwner.flush]: drains the dirty set in depth order
  /// and returns the elements this call actually rebuilt, in flush order —
  /// the drained dirty set exposed to harvest backends (ADR-0001 Decision 5).
  List<Branch> flushHarvest() => flush();
}
