# Genesis de-risking spikes — results (2026-06-11)

All five spikes from `docs/genesis-spike-handoff.md` ran in lenny, **green, each adversarially
verified** (independent skeptic agents re-ran every spike fresh and tamper-tested the checks on
/tmp copies — injected bugs flipped every suite red). Everything here is **untracked working-tree
state**: no commits, no ADRs written, no production scaffolding — per the spike-first constraint.
Beads: `lenny-dtcv`, `lenny-17qo`, `lenny-f5zn`, `lenny-vu1j`, `lenny-78r1` (all closed, with
detailed notes per bead).

## Verdicts

| # | Spike | De-risks | Verdict | Key evidence |
|---|---|---|---|---|
| 1 | Headless Flutter render dump (`packages/exploration_flutter/test/spike/`, log in `spike1_headless_dump/`) | genesis **A4 oracle** | green | Full framework runs in a plain shell under flutter_tester; `debugDumpRenderTree()` shows real laid-out geometry (root 800×600, RenderParagraph `Size(199.5, 20.0)` at `Offset(0,56)`). |
| 2 | Bare-VM ANSI cell grid (`spike2_cell_grid/`) | genesis **A4 fork B** | green | Pure-stdlib double-buffered cell diff → minimal ANSI: steady-state 16/2000 changed cells ≈ 60 bytes vs ~2982 full redraw (~2%). |
| 3 | Schema+codegen ⇄ A2UI round-trip (`spike3_schema_roundtrip/` + `spike3_flutter_harness/`) | genesis **A2 + A3** (load-bearing) | green | ONE `catalog.json` generates BOTH the Dart factory registry and the LLM tool schema (deterministic, tamper-tested); real A2UI v0.9 envelope deserialized via the generated registry, component id → `Perception.key`; whole-tree re-emission → identity-preserving keyed patch (`identical()`, incl. deep identity in a moved subtree); same 5 framework-free checks green under `dart test` AND `flutter test`. |
| 4 | Tree → terminal via Watch dirty set (`spike4_tree_terminal/`) | genesis **A4** | green | Event → `perceived()` → owner dirty set → `onNeedsHarvest` → `flushHarvest` → targeted repaint → ANSI diff. Locality hard-asserted (zero cells changed in static rects; static element never rebuilt). Update frames 0–38 bytes vs 1053 full redraw (~39×). |
| 5 | A2UI action round-trip, enforce/reject (`spike5_action_roundtrip/`) | genesis **A5** | green | Catalog-declared affordances flow into the tool schema (x-actions); live-tree hit-test gates (exists/mounted/declared/payload); enforce rebuilds exactly the target subtree; 4 rejection kinds leave the tree byte-for-byte untouched; staleness = v2 re-emission unmounts target → `staleUnmounted`; last-write-wins probe: arrival order, dirty set coalesces racing writes. |

Re-run commands are in each spike's `NOTES.md`.

## Findings ledger (carry into genesis)

**Spec:** A2UI **v0.9 renamed `surfaceUpdate` → `updateComponents`** (flat components, string
`component` discriminator, `children` as ordered id array, root by `id=="root"` convention, no
rootId field). The genesis A3 register entry and the handoff use the v0.8 name — fix on promotion.
Action message shape: `{name, surfaceId, sourceComponentId, timestamp, context}` (a2ui.org).

**`tree` API design feedback (from building against perception):**
- `PerceptionOwner`'s dirty set is private — render backends need the **drained dirty set exposed**
  (spike 4 had to fake dirty-region mapping with a builder-driven notifier). A `TreeOwner` flush
  should hand the backend what rebuilt.
- No `visitChildren` on elements — spikes walked by concrete element shape. `Branch` needs a
  traversal API.
- Keyed-reconcile config updates do **not** re-run ComponentElement builders (asset for spike 5's
  identity proof; needs an explicit decision in genesis: when does a config update imply rebuild?).
- Codegen seams wanted: catalog plugin keys (unknown type-level keys are silently dropped today),
  parameterized provenance headers, and a tree-builder parameterized over the registry (the one
  line spike 5 had to fork).
- `Isolate.resolvePackageUriSync` throws under flutter_test — resolve roots by walking to
  `.dart_tool/package_config.json` instead.
- Headless oracle practicalities (spike 1): multi-view binding needs `renderViews.single`; pin the
  deterministic `FlutterTest` font for exact text geometry; test binding ≠ production embedder.

**Consensus (parked, genesis A5):** the LWW probe supports the lean — writes apply in arrival
order, unflushed racing writes coalesce into one rebuild, intermediates are never rendered, and
`Applied{from,to}` records are the audit trail. Fund observable-intermediates separately if ever
needed.

## Deliberately not proven

Rasterization/compositing to pixels (spike 1 is layout-geometry only); production embedder
semantics (test binding); measured patch *minimality* (identity preservation is proven, byte
minimality implied); validator-executed JSON-Schema conformance (hand-walked); input
handling/raw-mode/resize/CJK width in the TUI path; multi-party consensus beyond LWW.

## Next phase (user-gated — do not start without Nico)

Scaffold `memento-engineering/genesis` (pub workspace + `tree`/`perception` skeletons + CLAUDE.md
carrying the ADR-0000 register rule), migrate `perception`, promote register entries A1–A8 to
genesis ADR-0001+ (Nico promotes; A8 already decided). The spike tree under `spikes/` is the
reference implementation evidence; it is disposable once genesis lands the real thing.
