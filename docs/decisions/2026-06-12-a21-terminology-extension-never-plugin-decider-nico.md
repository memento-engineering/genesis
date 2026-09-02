---
status: accepted
date: 2026-06-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a21-terminology-extension-never-plugin-decider-nico
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A21"
---
## A21 (2026-06-12) — Terminology: "extension", never "plugin"  ·  decider: Nico

**Decision:** memento.engineering does not use the term **plugin** in its own code, docs, or names — the seam word is **extension**. "Plugin" is reserved for third-party artifacts named that way by their own ecosystems (e.g. Flutter platform-channel plugins). Applied immediately: `CatalogPlugin` → **`CatalogExtension`**, `ActionsCatalogPlugin` → `ActionsCatalogExtension`, `defaultCatalogPlugins` → `defaultCatalogExtensions`, `Catalog.parse(extensions:)`, `lib/src/plugin.dart` → `extension.dart`; A19's wording updated in place. *(Keeper's note: Nico wrote "`TaxonomyExtension` not `TaxonomyPlugin`"; the as-built class was `CatalogPlugin`, so the rename followed the existing `Catalog*` shape — flag if `TaxonomyExtension` was meant literally.)*
**Why:** "plugin" is overloaded to meaninglessness; this is the same rule behind lenny's plugin→extension sweep (bead `lenny-4tvb`), now org-wide.
**Affects:** `genesis_taxonomy` API (renamed, gates green); future packages; genesis `CLAUDE.md` conventions (rule added). **Status:** promoted → ADR-0002 (CatalogExtension; "plugin" wording swept), 2026-06-13 (commit `cc4bf28`).

