/// Measurement domain on the tree spine.
///
/// `Perception extends Component`, `PerceptionElement extends Element`,
/// `PerceptionContext` is a capability extension of `BuildContext`, and
/// `PerceptionOwner` builds on `BuildOwner`.
///
/// The tree spine is re-exported in full: perception's public signatures
/// deliberately surface tree types, so consumers get `Component`/`Element`/
/// `BuildContext`/`BuildOwner` — and the composition layer, including
/// `Watch<T>`, which lives in tree's composition layer and perception consumes
/// via this re-export — from this one import.
library;

export 'package:genesis_tree/genesis_tree.dart';

export 'src/field.dart';
export 'src/inherited_perception.dart';
export 'src/node.dart';
export 'src/perception.dart';
export 'src/perception_context.dart' show PerceptionContext;
export 'src/perception_element.dart';
export 'src/perception_owner.dart';
export 'src/serialize.dart';
export 'src/stateful_perception.dart';
export 'src/stateless_perception.dart';
