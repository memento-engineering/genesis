---
status: accepted
date: 2026-11-10
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: a-render-element-paints-at-most-once-per-frame
  surfaces:
    - "packages/typesetting/lib/src/stage.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-9ny
  legacy-id: null
---

# A render element paints at most once per frame

## Context and Problem Statement

The typesetting stage's paint pass drains its dirty set parents first and
paints each dirty render element together with its whole render subtree. When
an element and one of its render ancestors were both dirty in the same frame,
the element was painted once by every dirty ancestor's subtree paint and once
more by its own, so a whole-tree update over a tree of depth d painted the
deepest elements d times: paint cost grew quadratically with depth. The stage
binding documented this as overlapping repaints deduped by the double buffer
rather than by skipping; this entry amends that documented behaviour. The
mechanism lives in the stage binding, `packages/typesetting/lib/src/stage.dart`.

## Decision Outcome

**D1.** Within one frame every render element paints at most once. A dirty
element that an ancestor's subtree paint has already reached in this frame is
not painted again, because that paint covered it. Parents still paint before
children, and frame 0 still paints synchronously at mount.

**D2.** A dirty element leaves the paint queue at the moment its paint
begins, whether it paints on its own or is reached by an ancestor's subtree
paint, and counts as repainted in that frame's record. A covered element
therefore buys no follow-up frame, and the record still names every dirty
element the frame served.

**D3.** A repaint request raised for an element after its paint in this frame
began is not served by that paint: it stays queued and is served by the one
follow-up pass the in-pass entry grants for work left over. Covering never
swallows a request the covering paint could not have seen.

**D4.** Only paint that actually reached an element covers it. When a paint
throws, the element whose own paint threw counts as attempted and leaves the
queue, wherever it sits in the subtree being painted, and every dirty element
the throwing paint had not yet reached stays queued for the next pass,
consistent with the in-pass entry's rule for throwing passes.

### Consequences

* Good, because a whole-tree repaint costs one paint per element instead of
  growing with tree depth.
* Good, because frame records and emitted bytes for existing scenes are
  unchanged: covered elements still report their rects.
* Neutral, because where a child's rect overflows its container into a later
  sibling's cells, the final cells follow plain tree order, the same result a
  single subtree paint already produces.

### Confirmation

This entry is falsified by any of: a frame in which any render element paints
twice; a covered element missing from that frame's repainted set or left
queued without a fresh request; a repaint request raised after an element's
paint began that no later frame serves; a descendant lost after an
ancestor's paint threw; or an element whose own paint threw being retried
automatically.
