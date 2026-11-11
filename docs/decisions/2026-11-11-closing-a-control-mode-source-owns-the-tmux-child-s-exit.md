---
status: accepted
date: 2026-11-11
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: closing-a-control-mode-source-owns-the-tmux-child-s-exit
  surfaces:
    - "packages/tmux/lib/src/control_source.dart"
    - "packages/tmux/lib/src/executor.dart"
    - "packages/tmux/lib/src/process_executor.dart"
    - "packages/tmux/lib/src/fake_executor.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-a7h
  legacy-id: null
---

# Closing a control-mode source owns the tmux child's exit

## Context and Problem Statement

The tmux control-mode observation source spawns one long-lived tmux control
client through the executor seam. Closing the source stopped reading, closed
the child's input and closed the event stream, but nothing waited for the
child to exit, and the real executor never passed the input's end on to tmux.
A closed source could leave a tmux process running indefinitely. The
connection the executor hands back carried no way to end its child by force,
so the source had nothing to fall back on when the child did not leave on its
own.

## Decision Outcome

**D1.** Closing a control-mode observation source owns the child's
termination. It ends the child's input, waits for the child to exit, and
forces termination when the child has not exited within a two-second bound,
so a completed close never leaves the child running.

**D2.** Output the child produced before it exited reaches listeners before
the event stream closes. The source stops reading only once the child is
gone. This amends the order first proposed for the work, which stopped
reading before ending the child's input and so would have discarded exactly
the remaining output a close should deliver.

**D3.** Closing is idempotent. Every close, whether a caller asked for it or
the connection ending caused it, shares one completion and does the work
once.

**D4.** The executor's control connection carries forced termination and
signals the child's exit, so the source stays testable against the fake with
no process spawned. Adding forced termination to the connection is a
breaking change to the executor seam and is released as one.

### Consequences

* Good, because a supervisor that closes a source can rely on the tmux child
  being gone, with no orphaned control clients accumulating.
* Good, because a cooperative child is never killed: ending its input is
  enough, and the bound only matters for a child that ignores it.
* Bad, because a close of an unresponsive child takes the full two seconds,
  and the bound is fixed rather than configurable.
* Bad, because every custom executor must now be able to end its control
  child by force.

### Confirmation

This entry is falsified by any of: a completed close with the child still
alive; output the child emitted before exiting that never reaches listeners;
a repeated close that throws or repeats work.
