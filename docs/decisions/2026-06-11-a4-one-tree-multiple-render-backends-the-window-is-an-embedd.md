---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a4-one-tree-multiple-render-backends-the-window-is-an-embedd
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A4"
---
## A4 (2026-06-11) — One tree, multiple render backends; "the window is an embedder choice" — *scoped to the rendering axis*  ·  AI

*(migrated from lenny A3; rescoped + overlap correction + retagged scoped)*
**Decision:** `tree` carries render backends beyond serialization: (a) a pure-Dart **cell/TUI backend** (character grid → ANSI; bare VM, no engine); (b) a **Flutter adapter** (windowed GUI); (c) **headless real Flutter** (`flutter_tester`) as a **conformance oracle only**, never a render path. A window is a property of the chosen embedder, not the framework.
**Scope (resolves the apparent 0001 conflict):** 0001 rejected a retained render tree *for the model-facing projection* — correct: JSON needs hierarchy + size (1-D), not geometry. A render tree is required only for **human-facing** backends (2-D cell/pixel geometry). Orthogonal backends off one element tree; no contradiction. **Sleeper win:** measurement + human-facing = a read-only TUI of the live Observation (lenny's inspector, reborn native-terminal).
**Overlap correction (vs the_grid):** grid's tmux runtime (ADR-0004) is process/session *supervision* (owns terminal real estate); a genesis cell backend *draws into* that real estate — complementary, not duplicative. grid's reconciler (ADR-0003) is a *convergence state machine over beads*; genesis's reconciler is the *tree keyed diff* — two reconcilers at two layers. The earlier "overlap" was **vocabulary collision**, which this factoring disambiguates.
**Why:** enables the agent↔human projection on the bare VM without Skia; the oracle proves the cell backend's layout matches Flutter's instead of asserting it.
**Affects:** package layout (a `tree_terminal`); lenny ADR 0001's render-tree rejection (now scoped to model-facing). **Status:** promoted → ADR-0004 (ratified Nico 2026-06-11).

