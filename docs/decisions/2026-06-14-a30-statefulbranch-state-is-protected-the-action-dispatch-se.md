---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a30-statefulbranch-state-is-protected-the-action-dispatch-se
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A30"
---
## A30 (2026-06-14) — `StatefulBranch.state` is `@protected`; the action-dispatch seam lives on the element, not via `.state`  ·  decider: Nico

**Decision (Nico, directed — resolves A28 flag 1):**
- **`StatefulBranch.state` is `@protected`** (was public, doc-marked "do not use in production"): a subclass-only accessor, **not** public API — external layers must not reach into a branch's `State`. `genesis_perception`'s `StatefulPerceptionElement.state` override is `@protected` likewise. Tests that read `.state` carry an `// ignore_for_file: invalid_use_of_protected_member`.
- **consent no longer reaches `.state`.** The dispatch seam is `Actionable` implemented **on the element** (the spike-5 "seam on elements"), resolved by `target is Actionable` on the live branch (`_actionableOf`). An actionable component declares `Actionable` on a `StatefulBranch`/`StatefulPerceptionElement` subclass (e.g. the fixture's `CounterElement`) that forwards to its own `State` — legitimate subclass access to the `@protected` getter. `Actionable` stays in `genesis_consent` (A28; that answer holds — only the *reaching* moved).
- **`tree` stays artifact-agnostic** — no action/dispatch/affordance vocabulary enters the spine (A11 upheld). The rejected alternative (a `useAction`/`ActionHost` hook in `tree`/`Sprout`) would have put action semantics in the generic engine; shot down.

**Why:** the `.state` reach was consent (an external layer) using a tree getter explicitly discouraged for production. `@protected` enforces the encapsulation at the analyzer; moving the seam onto the element gives consent a blessed, non-`.state` path while keeping the action contract in consent and the spine action-free.
**Affects:** amends A14 (tree `state` now `@protected`) and A15 (perception override); resolves A28 flag 1 (consent `_actionableOf` is now `target is Actionable`); A29 unaffected (`Sprout` has no `State`/`.state`). All six packages green (tree 145 / perception 104 / taxonomy 73 / typesetting 25 / dialogue 38 / consent 16); analyze + format clean. **Status:** promoted → ADR-0001 D3 (tree half) + ADR-0005 D7 (consent half), 2026-06-14.

