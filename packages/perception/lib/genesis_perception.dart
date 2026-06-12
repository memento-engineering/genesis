/// Measurement domain on the tree spine (perception; lenny ADR 0001 lineage).
///
/// `Perception extends Seed`, `PerceptionElement extends Branch`,
/// `PerceptionContext` is a capability extension of `TreeContext`, and
/// `PerceptionOwner` builds on `TreeOwner` (genesis ADR-0001 Decision 6).
///
/// The tree spine is re-exported in full: perception's public signatures
/// deliberately surface tree types (A12), so consumers get `Seed`/`Branch`/
/// `TreeContext`/`TreeOwner` — and the composition layer, including
/// `Watch<T>` (register A13: Watch lives in tree's composition layer;
/// perception consumes it via this re-export) — from this one import.
library;

export 'package:genesis_tree/genesis_tree.dart';

export 'src/field.dart';
export 'src/inherited_perception.dart';
export 'src/node.dart';
export 'src/perception.dart';
export 'src/perception_context.dart' show PerceptionContext;
export 'src/perception_element.dart';
export 'src/perception_owner.dart';
export 'src/stateful_perception.dart';
export 'src/stateless_perception.dart';
