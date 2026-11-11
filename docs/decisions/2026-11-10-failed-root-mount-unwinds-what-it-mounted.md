---
status: accepted
date: 2026-11-10
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: failed-root-mount-unwinds-what-it-mounted
  surfaces:
    - "packages/tree/lib/src/build_owner.dart"
    - "packages/tree/lib/src/element.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-9u0
---
## (2026-11-10) — A failed root mount unwinds what it mounted · decider: agent

**(D1)** A root mount that throws leaves the owner holding nothing. Every
element that mount attached is unmounted before the error propagates,
unchanged and with its own stack trace, and the owner then accepts a new root.

**(D2)** The owner learns which elements mounted from a record that the element
base's mount reports into, kept only for the duration of a root mount. The
element base gains no state, callback or override point, so the Branch purity
invariant of genesis#adr-0001-foundations Decision 3 holds.

**(D3)** Teardown unmounts each recorded element that no recorded parent
reaches, latest-mounted first. A subtree that finished mounting whole comes
down through its own unmount, exactly as a normal unmount takes it. This
depends on the traversal contract: an element reports every child its unmount
tears down.

**(D4)** A teardown error during the unwind is dropped. The mount error is the
one the caller sees, and an element whose own teardown threw is left as that
teardown left it, as under a normal unmount.

**(D5)** Only the root mount unwinds. A rebuild that throws during a flush
keeps its current behaviour.

**Why:** an embedder that mounts a tree and disposes the owner on failure had
no way to reach the partial tree, so every State and every provider-created
value it held leaked. The provider layer's own failed-mount seam names the case
it cannot reach: a subtree fully mounted under a container whose later sibling
failed.

**Relation to existing entries.**

- genesis#a29-sprout-a-hooks-style-stateful-primitive-in-tree-s-compos rules
  that hook disposal "runs slot teardowns in **reverse order** … each
  **guarded** so one throwing user cleanup can't strand a sibling teardown or
  break the tree unmount (the first error rethrows after all teardowns +
  `super.unmount`)". That contract governs the slots inside one element's
  teardown and is untouched here: an element unmounted by this unwind still
  runs its own teardown, hooks included, by that rule. D3 and D4 apply the same
  shape one level up, across elements: reverse order, each element guarded so
  a throwing teardown strands no sibling. They differ on which error the caller
  sees. Inside one element, no earlier error is in flight, so the first teardown
  error rethrows. During this unwind, a mount error is already in flight and is
  the cause the caller must see, so a teardown error does not replace it.
- genesis#adr-0006-pull-free-build makes `State.initState` the opener and
  `State.dispose` the closer of a State's managed resources. This entry keeps
  that pairing whole on the failure path: every State whose initState ran
  during the failed mount reaches its dispose once, through its element's
  normal unmount, and no State is disposed by any other route. A State whose
  dispose itself throws is left where its element's unmount leaves it (D4), as
  a normal unmount leaves it today; the unwind never re-runs a dispose.
- genesis#element-and-build-context-stay-separate-under-their-new-names rules
  that the mounted node never implements the build context. The unwind works on
  elements only, from the owner; it hands no element out through a context and
  adds nothing to the context surface. A context held from a torn-down element
  reports itself unmounted, as after any unmount.
- genesis#lifecycle-phase-guard-is-public-tree-api: each dispose the unwind
  reaches still runs inside the dispose phase, through the stateful element's
  own unmount; the scheduler and flush ordering are unchanged.

**Falsified by:** a failed root mount that leaves a State undisposed, disposes
one twice, or rethrows anything but the mount error.

**Status:** accepted.
