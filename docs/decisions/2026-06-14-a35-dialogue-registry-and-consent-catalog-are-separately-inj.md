---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a35-dialogue-registry-and-consent-catalog-are-separately-inj
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A35"
---
## A35 (2026-06-14) — dialogue registry and consent catalog are separately injected with no cross-check; assert type-name agreement  ·  AI

**Decision:** since `DialogueSurface` takes a `ComponentRegistry` and `ConsentRouter` takes a `Catalog` as independent objects, a consumer must generate both from one catalog source and assert at startup that the catalog's type names are a subset of `registry.entries.keys` (render-root types are registry-only by design — they afford nothing and are not LLM-addressable).
**Why:** no code cross-checks them; a name drift (registry builds `screen`, catalog declares `stage`) silently degrades every action to `undeclaredAction` (Gate 2 finds an empty actions map) with no error.
**Affects:** `genesis_dialogue`/`genesis_consent` (separate injection points); `genesis_taxonomy` (single-source builder); apps/console (startup subset-assert). A shared assertion helper in a future genesis release is possible. **Status:** pending.

