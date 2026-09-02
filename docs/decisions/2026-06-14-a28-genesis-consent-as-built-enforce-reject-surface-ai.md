---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a28-genesis-consent-as-built-enforce-reject-surface-ai
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A28"
---
## A28 (2026-06-14) — `genesis_consent` as-built enforce/reject surface  ·  AI

**Decision (as built; 16 tests, two-skeptic adversarial verification + 3 tamper probes — staleness-collapse, affordance-gate-bypass, and enforce-without-`perceived()` each tripped a distinct test; full workspace green: tree 120 / perception 104 / taxonomy 73 / typesetting 25 / dialogue 35 / consent 16).** The action router ADR-0005 specifies, productionized against the as-built packages (consumes `genesis_dialogue` `ActionEvent`/`DialogueSurface`, `genesis_taxonomy` `Catalog`, the live `genesis_tree`/`genesis_perception` tree). Pure Dart, bare VM; no "plugin" wording; tests use perception `Node`/`Field` + a stateful `Counter` fixture (A22).
- **`ConsentRouter{surface, catalog}` is the front door.** It owns the emission ledger the hit-test needs — `_everSeenIds` (union across emissions; `unknownComponent` vs `staleUnmounted`) and `_typeById` (replaced per emission; affordance lookup) — which dialogue's `DialogueSurface` does not track (A25). So `mount`/`apply` are driven **through the router** (it forwards to the surface and records); calling `surface.mount/apply` directly would desync the ledger. A renderer still shares the surface's `TreeOwner`.
- **Three gates (ADR-0005 D2), none hardcoded:** (1) exists/mounted — walk the live tree FRESH per call (no cached refs, A8); (2) catalog-declared — `catalog.typeNamed(type).actions`; (3) payload — delegated to the target state. `route` returns a sealed `ConsentOutcome` = `Applied{action, componentId, ActionChange{from,to}}` | `Rejected{kind, …, message}`.
- **`RejectionKind` is a flat enum** (`unknownComponent`/`staleUnmounted`/`undeclaredAction`/`badPayload`), not a per-variant sealed hierarchy like dialogue's exceptions — the outer `ConsentOutcome` is the sealed union; the four reasons share a shape and differ only in which optional field (`availableActions`/`payloadError`) is populated; `Rejected.message` switches exhaustively (A6 satisfied). **Deliberate divergence from dialogue's style — flag.**
- **Enforce via the target state (D4):** `Actionable{validateAction (pure, gate 3) / applyAction (mutates via `perceived()`/setState)}`. Splitting pure-validate from mutate is what makes "`badPayload` leaves the tree byte-for-byte untouched" true **by construction** (validation runs before any mutation), not by domain discipline.
- **LWW (D6) parked, unchanged:** synchronous in-order application; `ActionChange{from,to}` is the audit trail; two unflushed writes coalesce to one rebuild (proven, not vacuous).

**Flagged for Nico (AI decisions not covered by a ratified ADR — promote or shoot down):**
1. **Dispatch seam reaches the target `State` via `StatefulBranch.state`** — a getter `genesis_tree` doc-marks "do not use in production." Using it is the ADR-sanctioned exception (D4 mandates reaching the target state), but the proper fix is a **first-class branch-level action-dispatch hook on `tree`** (exactly spike 5's flagged "production wants a first-class action-dispatch seam on elements"). **This wants its own tree-API decision/bead.**
2. **The `Actionable` seam interface lives in `genesis_consent`** and is implemented on a domain's `State` (e.g. `PerceptionState … implements Actionable`) — so any action-affording domain depends on consent. Where the dispatch interface lives is an architecture call (A22 is satisfied: only test fixtures import consent, perception lib does not).
3. **Affordances are read from a runtime `Catalog.parse(...).typeNamed(t).actions` lookup, NOT a generated `actions.g.dart` map.** ADR-0005 D1/D2 text references the spike's generated `componentActions`/`wireTypeOfPerception`; `genesis_taxonomy` (A19) never carried that projection forward, so consent consults the parsed runtime catalog. The "one source of truth" property still holds (LLM `x-actions` and the router's check both derive from `CatalogType.actions`), but the **mechanism diverges from the ratified text** — a generated affordance map is a possible future taxonomy projection if runtime parse cost ever matters.
4. **A DAG-shared component id (one id referenced by two parents → built once per reference by `buildSeedTree`, A19) resolves to >1 mounted branch; `route` throws `StateError`** rather than silently enforcing against an arbitrary copy (repro skeptic's M1). Treated as an authoring error (a surface must address each component by a unique id), consistent with the non-`Actionable` `StateError` — NOT a fifth `RejectionKind`. **A semantic call: should a duplicated-id action be a developer error (current) or get a structured actor-facing rejection?**
5. **`StateError` (developer error) vs `Rejected` (actor feedback)** boundary: catalog-declares-but-State-can't-honor, and the DAG-shared-id case, throw; the four actor-input failures return `Rejected`. Keeps the rejection taxonomy actor-feedback-only.
6. **Single-surface v1: a `surfaceId` mismatch folds into `unknownComponent`** (the spike-5 fold; no fifth kind), and the affordance check assumes the router's `catalog` matches the surface's `registry`.

**Affects:** ADR-0005 at next promotion (the as-built mechanism deltas above, esp. flags 1/3/4); a possible `genesis_tree` action-dispatch-hook decision (flag 1); a possible `genesis_taxonomy` generated-affordance-map projection (flag 3). **Status:** promoted → ADR-0005 D7, 2026-06-14 (flag 1 resolved by A30; flag 4 DAG-id ratified to `StateError`; flags 3/6 ratified as-built).

