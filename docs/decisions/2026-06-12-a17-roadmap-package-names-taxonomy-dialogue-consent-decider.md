---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a17-roadmap-package-names-taxonomy-dialogue-consent-decider
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A17"
---
## A17 (2026-06-12) — Roadmap package names: `taxonomy` / `dialogue` / `consent`  ·  decider: Nico

**Decision (resolves A16(e)'s floated slot):**
- Codegen/catalog = **`genesis_taxonomy`** — the catalog classifies node species and their traits; the generated registry is the taxonomy's type system (replaces the `tree_codegen` working name from A2/ADR-0002).
- A2UI wire = **`genesis_dialogue`** — names the bidirectionality: structured two-way exchange between agent and surface (ADR-0003).
- Action router = **`genesis_consent`** — affordances declare what may be asked; the router grants or withholds; every rejection kind is a refusal of consent, `staleUnmounted` is consent *revoked* because the world changed (ADR-0005).
Rejected this round: `grammar`/`koine`/`covenant` (first float), `nomenclature`/`lexicography`/`orthography`, `correspondence`/`vernacular`/`shorthand`, `warrant`/`liturgy`/`accord` (re-roll bench).
**Why:** three human acts — classify, converse, consent — naming the mechanism, per A16's register (faculties/achievements, no agent-nouns).
**Affects:** beads `genesis-vb2`/`genesis-6fv`/`genesis-hjj` (retitled); ADR-0002/0003/0005 working names at next promotion pass. **Status:** promoted → ADR-0002/0003/0005 (package names), 2026-06-13 (commit `cc4bf28`).

