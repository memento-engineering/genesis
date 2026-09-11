---
status: accepted
date: 2026-09-10
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: mid-flush-dirty-must-target-a-descendant
  surfaces:
    - "packages/tree/lib/src/branch.dart"
    - "packages/tree/lib/src/tree_owner.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-gic
  legacy-id: null
---

# Mid-flush dirties must target a descendant

## Context and Problem Statement

Genesis permits branches to become dirty while a flush is already building
another branch. Instrumentation across the Genesis workspace and the Grid
engine observed 149 such dirties in 1,192 tests. Every target was strictly
deeper than the branch building at the time, and 146 came from
`InheritedBranch.notifyDependents`.

The earlier premise that Flutter prohibits this entire class of scheduling was
incorrect. The safety boundary is ancestry, not a blanket prohibition: a
descendant will still be reached because the tree builds parents before
children, while another target might have already been passed over in the
current flush.

Genesis also needs to distinguish the branch whose build hook is executing
from the branch most recently drained from the dirty set. A parent-first update
cascade can synchronously rebuild descendants of that drained branch. Using
the drained branch as the scope would therefore admit invalid dirties from a
nested build.

## Decision Outcome

Adopt exactly Flutter's ancestry rule from
[Element.markNeedsBuild](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/framework.dart)
in `flutter/packages/flutter/lib/src/widgets/framework.dart`. Flutter permits
a dirty during build when
`_debugIsDescendantOf(owner._debugCurrentBuildTarget)` holds because parents
build before children: a dirty descendant is always built, whereas any other
branch may not be visited during the current flush pass.

`TreeOwner` tracks the branch whose `performRebuild` hook is currently
executing, including nested update cascades, and assertion-checks that a branch
dirtied during that scope is its descendant. The check is assertion-only,
matching Flutter's debug ancestry check. `InheritedBranch.notifyDependents`
needs no exception because a dependent is always a descendant of the inherited
branch on which it depends.

This deliberately distinguishes
`genesis#release-mode-tree-invariants-throw-in-release`, which keeps the three
existing corruption guards release-enforced. The ancestry rule is a build-order
diagnostic: violating it risks deferring a visit, but does not corrupt the tree
or unbound the drain loop. That existing corruption ruling remains unchanged
and is not updated by this decision.

### Consequences

* Good, because legal descendant notifications remain synchronous in the
  current flush pass.
* Good, because nested cascades are checked against the branch actually
  building rather than the less precise drained ancestor.
* Bad, because ancestry violations are diagnosed only when assertions are
  enabled.
