---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a5-the-projection-manipulation-substrate-four-dynamics-four
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A5"
---
## A5 (2026-06-11) — The projection/manipulation substrate: four dynamics, four audiences, enforce/reject  ·  AI (consensus lean: Nico)

*(migrated from lenny A4)*
**Decision:** frame the system as *interfaces-as-projections* (`get` projection + `put` handles). Four dynamics, bound to lenny ADR 0001 vocabulary: **Context** = the projection; **Attention** = the subscription graph (`Watch`) + the parked focus-policy knob; **Affordance** = 0001's parked "action/affordance half"; **Intent** = the thing the framework does not supply (model/human/code brings it). **Validation/invalidation = enforce/reject = 0001's "action validation == hit-testing."** Four audiences — human/agent/machine/self — differ only on *who supplies Intent* and *how Context renders* (the A1 rendering axis); **agent→machine is the tool-call projection.** Multi-party consensus on a rejected write is **parked, leaning `setState`** (last-write-wins / silent invalidate).
**Why:** names what 0001 §3 half-formalized and parked, and generalizes single-app-observe → multi-party substrate. Consensus is the genuinely novel surface, deferred until the spikes inform it.
**Affects:** unparks lenny ADR 0001 §3; reconcile vocabulary with the_grid ADR-0002 "reactive domain projections" (same concept over beads). **Status:** promoted → ADR-0005 (ratified Nico 2026-06-11); multi-party consensus NOT promoted — stays parked, lean last-write-wins.

