---
status: accepted
date: 2026-11-10
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: in-pass-frame-requests-buy-one-follow-up-for-work-left-over
  surfaces:
    - "packages/typesetting/lib/src/stage.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-hex
  legacy-id: null
---

# In-pass frame requests buy one follow-up for work left over

## Context and Problem Statement

The typesetting stage runs one frame pass at a time, and every public callback
a pass runs — component builds during the owner's flush, layout, paint, the
output sink, and the per-frame observer — can ask for more work: a repaint, a
relayout or a rebuild. The stage ignored any such request while a pass was
running. The work was recorded as dirty but nothing scheduled a frame for it,
so it sat until an unrelated later request happened to start one. A pass that
threw had no stated behaviour either: whether its unreached work survived, and
whether the scheduler could run again, was an accident of the code. The
mechanism lives in the stage binding, `packages/typesetting/lib/src/stage.dart`.

## Decision Outcome

**D1.** A frame request raised while a pass runs is never dropped. When that
pass completes normally and leaves work outstanding, exactly one follow-up
pass is scheduled, and every request raised during the pass coalesces into
it. A request raised during the follow-up is treated the same way.

**D2.** A request whose work the running pass still consumes is served by
that pass and buys no follow-up. A repaint asked for by a build before the
paint step, or a rebuild asked for while the owner is still flushing, is done
in the frame that is running; scheduling another frame for it would only add
an empty wakeup.

**D3.** A throwing pass propagates its error unchanged and schedules no
follow-up, so a deterministic fault cannot loop. It leaves the scheduler able
to run the next requested pass, and work it had not yet reached — elements
still waiting to paint, a relayout not yet done — stays queued for that pass.
An element whose own paint threw counts as attempted and leaves the queue, so
one faulty element cannot wedge every later frame. Nothing is retried
automatically.

**D4.** A detached stage records and schedules nothing for any request.

### Consequences

* Good, because no request raised from inside a frame can strand its work,
  and the common case — builds marking their own paint — costs no extra
  frame.
* Good, because a throw is a bounded event: one error, no loop, and the next
  explicit request picks up where the throw stopped.
* Bad, because a throwing pass leaves queued work idle until something else
  asks for a frame; the stage deliberately does not retry on its own.

### Confirmation

This entry is falsified by any of: a recorded frame that no outstanding work
explains; a request raised during a pass whose work no later frame ever
serves; a throw that loops, or that leaves later requests unscheduled.
