/// Domain-free Seed/Branch tree engine extracted from Flutter (genesis
/// ADR-0001).
///
/// The spine: `Seed` (immutable config) mounts as `Branch` (persistent node),
/// with `TreeContext` as a separate capability handle — never the `Branch`
/// itself — and `TreeOwner` as the scheduler (ADR-0001 Decision 2). The
/// composition layer (`ComponentBranch`, `StatelessSeed`/`StatefulSeed` +
/// `State`, `InheritedSeed`, `Watch`) is EXPERIMENTAL under the two-consumer
/// rule (ADR-0001 Decision 3).
library;

export 'src/branch.dart' hide InheritedBranchBase;
export 'src/component_branch.dart';
export 'src/inherited.dart';
export 'src/seed.dart';
export 'src/sprout.dart';
export 'src/stateful.dart';
export 'src/stateless.dart';
export 'src/tree_context.dart' show TreeContext;
export 'src/tree_owner.dart';
export 'src/watch.dart';
