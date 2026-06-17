/// Domain-free Seed/Branch tree engine — Flutter's element/reconciliation
/// model extracted to pure Dart.
///
/// The spine: `Seed` (immutable config) mounts as `Branch` (persistent node),
/// with `TreeContext` as a separate capability handle — never the `Branch`
/// itself — and `TreeOwner` as the scheduler. The composition layer
/// (`ComponentBranch`, `StatelessSeed`/`StatefulSeed` + `State`,
/// `MultiChildSeed`, `InheritedSeed`, `Watch`) is EXPERIMENTAL and may change
/// before 1.0.
library;

export 'src/branch.dart' hide InheritedBranchBase;
export 'src/component_branch.dart';
export 'src/inherited.dart';
export 'src/multi_child.dart';
export 'src/seed.dart';
export 'src/sprout.dart';
export 'src/stateful.dart';
export 'src/stateless.dart';
export 'src/tree_context.dart' show TreeContext;
export 'src/tree_owner.dart';
export 'src/watch.dart';
