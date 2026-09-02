---
status: accepted
date: 2026-06-16
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a41-multichildseed-multichildbranch-a-multi-child-container
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A41"
---
## A41 (2026-06-16) — `MultiChildSeed`/`MultiChildBranch`: a multi-child container in `tree`'s composition layer  ·  AI

**Context (the_grid M4 config-substrate discussion, 2026-06-16):** the_grid is adopting `genesis_tree` as its desired-state authoring substrate (Grid → Rig → {Order, Formula, Step} Seeds). Those topology nodes are inherently multi-child (a Grid has many Rigs; a Rig has many Orders/Steps), but the composition layer was single-child only: `ComponentBranch.build()` returns ONE child Seed (`updateChild` at slot 0). The keyed *engine* already supported many children (`Branch.updateChildren`, ported under A18, hardened with the duplicate-key guard under A38), but the only multi-child *container* was the `Node`/`NodeBranch` **test fixture** — A14 deliberately kept it out of lib code ("the container artifact lives in `perception`") because there was no second consumer for a generic container.

**Decision (as built; additive — the spine is untouched, perception's conformance gate holds):**
- **`MultiChildSeed extends Seed`** — carries `final List<Seed> children` (default `const []`) declared directly in config (the `MultiChildRenderObjectWidget` analogue), `abstract` so each container *kind* is its own reconciliation tag (`Seed.canUpdate` keys on `runtimeType`; the A29 constraint — two kinds sharing this base directly would reconcile into one another). Subclasses pass children up and may add typed fields (`class Grid extends MultiChildSeed { const Grid(List<Rig> rigs) : super(children: rigs); }`).
- **`MultiChildBranch extends Branch`** — keyed-reconciles the declared children via the existing `Branch.updateChildren` (mount → first-reconcile, `performRebuild` → `updateChildren`, `visitChildren` over them, unmount → reconcile-to-empty). The `NodeBranch` fixture's exact shape, promoted to public composition-layer API so consumers stop hand-rolling it. **Concrete and reusable across kinds** (like `StatelessBranch` across stateless seeds), but subclassable for a domain that wants an artifact response (extend `performRebuild` after `super` — the RenderObjectElement pattern). Matched children (keyed by key, unkeyed by position) keep branch identity across rebuilds; new mount, removed unmount, order follows `children`; the A18 identical-skip and the A38 duplicate-key debug guard are inherited from `Branch`.
- **Placement = composition layer, beside `StatelessSeed`/`StatefulSeed`/`Sprout`** (new `packages/tree/lib/src/multi_child.dart`, EXPERIMENTAL library marker; exported from the `genesis_tree` barrel). Reconciles with A14/A11/A31: what stays domain-owned is the container *artifact* (perception's `Node`, which carries measurement meaning); what's promoted here is the artifact-agnostic *composition* base — pure identity + keyed reconcile of declared children, no artifact response, no build contract — so Branch purity (A31) is upheld. `perception` inherits the new types for free via its full tree re-export (A15); no perception change.
- **EXPERIMENTAL, by the two-consumer rule (ADR-0001 D3):** the composition layer freezes only after a second consumer beyond `perception`. the_grid is that second consumer for the container shape; `MultiChildSeed`/`MultiChildBranch` ship experimental until it lands.

**Why:** multi-child is a general tree capability, not a the_grid domain concern; it belongs on the spine beside the single-child component seeds, mirroring Flutter's own factoring (`MultiChildRenderObjectElement` is framework core; Row/Column/Stack subclass it). The engine primitive existed; this is the ergonomic, public composition base.

**Possible naming/shape flags for Nico (defaults applied; flip any):** name `MultiChildSeed`/`MultiChildBranch` (mirrors `MultiChildRenderObjectWidget`/`Element` and the `*Seed`/`*Branch` family) · `children` is a **concrete field** (Flutter-identical), not an abstract getter (the genesis component idiom uses abstract `build`/`createState`, but a list is data, not a contract) · `MultiChildBranch` is concrete-but-subclassable, not abstract.

**Affects:** `packages/tree/lib/src/multi_child.dart` (new), `genesis_tree.dart` barrel (export + composition-layer doc), `packages/tree/CHANGELOG.md` (0.1.3) + pubspec (0.1.3; consumers pin `^0.1.0`, satisfied — no inter-package constraint change); ADR-0001 D3 (composition-layer contents) at next promotion; the_grid config-substrate adoption (the freezing second consumer). 14 new tests (`packages/tree/test/multi_child_test.dart`: mount/order, visitChildren, keyed-reorder identity, mount-new/unmount-removed, distinct-kind reconcile tags, unkeyed positional, identical-skip, nested Grid→Rig→Step topology + deep-reorder identity, transparent component composition, duplicate-key guard); tree 148→162, full workspace green (perception 104 unchanged); analyze + format clean. **Status:** pending.

