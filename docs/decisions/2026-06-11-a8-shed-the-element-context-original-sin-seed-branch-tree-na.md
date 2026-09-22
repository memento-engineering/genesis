---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a8-shed-the-element-context-original-sin-seed-branch-tree-na
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by:
    - element-and-build-context-stay-separate-under-their-new-names
  bead: null
  legacy-id: "A8"
---
## A8 (2026-06-11) — Shed the Element≡Context "original sin"; `Seed`/`Branch`/`tree` naming  ·  decided: Nico

**Decision (Nico, 2026-06-11) — shed the sin:** the mounted node does **not** implement the build context. `TreeContext` is a **distinct capability handle** passed to `build()`, never the `Branch` itself — sheds Flutter's context-leak bug class (held past validity / used across async gaps), which matters *more* here than in Flutter because agents routinely hold handles across async gaps. Diverges deliberately from lenny ADR 0001's `PerceptionElement implements PerceptionContext` (which re-committed Flutter's `Element implements BuildContext`).
**Naming (decided):** **`Seed`** = immutable config (Widget analogue — "planted, describes what grows") → **`Branch`** = mounted, persistent node (Element analogue); **`TreeContext`** = the separate handle; **`TreeOwner`** = scheduler; package **`tree`**.
*(The literal "original sin" comment is not present in the installed Flutter SDK `/Users/nico/flutter` — reworded/removed in this version; this entry records the design fork, not the quote.)*
**Affects:** `tree` base-type API; genesis sheds Flutter's context-leak class of bug. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

