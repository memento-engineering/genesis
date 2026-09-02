---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a9-config-update-re-runs-the-builder-flutter-style-rebuild-r
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A9"
---
## A9 (2026-06-11) — Config update re-runs the builder (Flutter-style rebuild rule)  ·  decider: Nico

**Decision (reworded 2026-06-11 post-discussion, A11):** in genesis `tree`, when keyed reconcile updates a mounted `Branch` in place (canUpdate: same runtimeType + key, new `Seed`), the update **invokes the Branch's rebuild hook**. `Branch` core fixes only *that* update reaches the hook; the composition layer (A11) defines the hook as re-running `build()` (Flutter `StatelessElement.update` semantics), while non-component branches define their own artifact response (Flutter `RenderObjectElement.update` analog). Diverges deliberately from perception's current behavior (update swaps config without re-running component builders), which spike 5 surfaced as needing a decision.
**Why:** expression surfaces must re-render on prop change with no manual plumbing; element-identity preservation (the A3 crux) holds either way, so spike 5's proofs are unaffected. Chosen by Nico from the post-spike decision set.
**Affects:** `Branch.update`/`TreeOwner` flush semantics; the perception rebuild (A10 campaign) inherits the rule. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

