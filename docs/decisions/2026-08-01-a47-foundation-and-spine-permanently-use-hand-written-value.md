---
status: accepted
date: 2026-08-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a47-foundation-and-spine-permanently-use-hand-written-value
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A47"
---
## A47 (2026-08-01) — foundation and spine permanently use hand-written value semantics · AI

**Decision:** `genesis_foundation` and the `genesis_tree` spine permanently use hand-written immutable value types, equality, `copyWith`, and codecs where needed, while retaining compiler-checked exhaustive switches. Freezed sealed unions with json_serializable remain the convention outside these two layers. This is a settled scope rule, not a temporary deviation. Independently, stable Freezed through 3.2.5 requires `build ^2/^3`, which cannot co-resolve with `genesis_taxonomy`'s direct `build ^4.0.6`.
**Affects:** `packages/foundation` and `packages/tree`.
**Status:** PROMOTED (Nico, 2026-08-01) into ADR-0001 Decision 7's Types convention.

