/// Domain-free Component/Element tree engine.
/// model extracted to pure Dart.
///
/// `Component` is immutable configuration, `Element` is its mounted identity,
/// and `BuildContext` remains a separate capability handle. `BuildOwner`
/// schedules synchronous rebuilds. Composition APIs remain experimental until
/// they satisfy the recorded two-consumer rule.
library;

export 'package:genesis_foundation/genesis_foundation.dart';

export 'src/build_context.dart' hide createBuildContext, createTreeContext;
export 'src/build_owner.dart';
export 'src/buildable_element.dart';
export 'src/component.dart';
export 'src/element.dart'
    hide InheritedBranchBase, InheritedElementBase, debugParentOf;
export 'src/hook_component.dart';
export 'src/inherited.dart';
export 'src/key.dart';
export 'src/lifecycle_provider.dart';
export 'src/multi_child.dart';
export 'src/provider.dart';
export 'src/single_child.dart';
export 'src/stateful.dart';
export 'src/stateless.dart';
export 'src/tree_lifecycle_participant.dart';
export 'src/tree_lifecycle_phase.dart';
export 'src/watch.dart';
