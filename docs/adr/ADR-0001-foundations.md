# ADR-0001 — Foundations for genesis

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A1, A6, A8, A9, A10, A11, A12
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** genesis is the shared substrate extracted from lenny's `perception` work — the Seed/Branch/keyed-reconcile engine Flutter proved, minus Flutter. Its consumers are `com.nicospencer/lenny` (the testing harness, via `perception`) and `engineering.memento/the_grid` (the platform SDK). The design lineage is lenny ADR 0001 (`com.nicospencer/lenny/docs/adrs/0001-declarative-perception-framework.md`), which migrates here with the code; this ADR records where genesis deliberately diverges from it. Every decision below was de-risked by the five 2026-06-11 spikes (lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`), all green with adversarial verification. **Spike evidence is working-tree-only**: the consolidated ledger lives untracked at `com.nicospencer/lenny/spikes/RESULTS.md` with per-spike `NOTES.md` — cited here as fact, but not durable. Companion ADRs planned from the same register: ADR-0002 Schema-first codegen (A2), ADR-0003 A2UI wire format (A3), ADR-0004 Render backends (A4), ADR-0005 Projection/action substrate (A5). Register entry A7 (grid snapshot-diff vs genesis keyed reconcile) remains open and is **not** promoted by any of them.

---

## Decision 1 — Substrate factoring + the two-axis model *(promotes A1)*

**genesis is the shared engine; `perception` and `the_grid` are domain consumers, not owners of the substrate.** This resolves the perception↔grid "one substrate or two?" question — neither: genesis is the root both build on.

Two orthogonal axes govern every projection the substrate serves:

| Axis | Values |
|---|---|
| **Authoring** (the tree's *role*) | **measurement** — read-only; the model never constructs nodes, its only `put` is a hit-tested action on the world · **expression** — read-write; surfaces authored directly |
| **Rendering** (who consumes) | **model-facing** — serialize, no geometry · **machine-facing** — typed structs · **human-facing** — render tree, 2-D geometry |

The axes dissolve the apparent conflicts in A3 and A4: each is a different cell of the 2-axis space, and lenny ADR 0001 occupied exactly one cell (measurement + model-facing) — correctly. The wire format (ADR-0003) lives on the expression row; the render-tree question (ADR-0004) lives on the human-facing column; lenny's "the model never constructs Perceptions" survives intact as the integrity rule of a measurement.

**Repo/package layout** (repo `genesis`, local checkout `engineering.memento/genesis`; org move at launch per Decision 8):

| Package | Contents | When |
|---|---|---|
| `packages/tree` | the engine: `Seed` → `Branch`, `TreeContext`, `TreeOwner`, keyed reconcile | now |
| `packages/perception` | the measurement domain: `Perception`/`PerceptionContext`/`PerceptionOwner`, rebuilt on `tree` | now (migrates from lenny) |
| `packages/tree_codegen` | schema → factory registry + LLM tool schema (register A2 → ADR-0002) | anticipated |
| `packages/tree_terminal` | cell/TUI human-facing backend (register A4 → ADR-0004) | anticipated |

**Consequence:** lenny ADRs 0001/0002 (perception design + migration) migrate here when the code moves; perception keeps its domain vocabulary as a consumer of `tree`, that vocabulary mapping onto tree types by subclassing (Decision 6).

## Decision 2 — The tree spine: `Seed` → `Branch`; `TreeContext` is a separate handle *(promotes A8)*

**Naming:** **`Seed`** = immutable config (the Widget analogue — planted, describes what grows) → **`Branch`** = mounted, persistent node (the Element analogue) · **`TreeContext`** = the build-time capability handle · **`TreeOwner`** = the scheduler (dirty set + flush) · package **`tree`**.

**The fork — shed Flutter's Element≡BuildContext "original sin":** `Branch` does **not** implement `TreeContext`. The context is a *distinct capability handle* passed to `build()`, never the mounted node itself. Flutter's `Element implements BuildContext` makes every build context a live tree node that can be held past validity or used across an async gap — a bug class Flutter mitigates with `mounted` checks and lints. It matters *more* here than in Flutter, because agents routinely hold handles across async gaps: an agent reads a projection, deliberates for seconds, then acts. lenny ADR 0001 re-committed the sin (`PerceptionElement implements PerceptionContext` — visible today at `packages/perception/lib/src/perception_element.dart`, line 10); genesis deliberately diverges.

**Spike 5 is the executable argument.** Its action router holds no element references at all — the agent's handle is a component *id*, hit-tested fresh against the live tree on every route call. When a v2 re-emission unmounts the target between the agent reading the surface and firing the action, the action rejects as `staleUnmounted` — distinguishable from `unknownComponent` via an ever-seen-id set — and every rejection path leaves the tree byte-for-byte untouched (`spikes/spike5_action_roundtrip/NOTES.md`, test e). "The projection moved under the actor" is first-class and detectable precisely because nothing the actor holds *is* the tree. A context handle that is the `Branch` would re-open that hole from the inside; a separate, invalidatable `TreeContext` closes it by construction.

*(Register note, carried verbatim: the literal "original sin" comment is not present in the installed Flutter SDK at `/Users/nico/flutter` — reworded/removed in that version; the entry records the design fork, not the quote.)*

## Decision 3 — Layering: `tree` owns structure + composition; artifact semantics are domain-owned *(promotes A11)*

**`Branch` core is artifact-agnostic** — identity, lifecycle, keyed reconcile, dirtiness, and **one abstract rebuild hook** (the `performRebuild` analog). It carries **no build contract**. The Flutter precedent is exact: `Element` itself never promises a build — `ComponentElement` (build → child widgets) and `RenderObjectElement` (render artifacts) are two artifact semantics under one tree, and the base class is agnostic to both.

A thin **composition layer** inside `tree` defines the hook as re-running `build()`: the `ComponentBranch` analog (build → child `Seed`s); `Stateless`/`Stateful` + `State` with the neutral setState-analogue; `Inherited`; and `Watch` (register A13, pending). The composition layer ships **experimental under the two-consumer rule** — its API freezes only after `perception` AND one expression surface both consume it.

**Artifact semantics are domain-owned.** Harvest/Observation/Digest/**token budget** (== constraints — Flutter's *render*-tree concern, never Element's) belong to `perception` outright; wire/actions/terminal are sibling expression-row packages that `perception` never imports.

This answers the "overloading genesis" worry structurally rather than by discipline: genesis is a seed/branch tree, full-stop.

## Decision 4 — Config update invokes the rebuild hook *(promotes A9, reworded at ratification per A11)*

When keyed reconcile updates a mounted `Branch` in place (`canUpdate`: same runtimeType + key, new `Seed`), the update **invokes the Branch's rebuild hook**. `Branch` core fixes only *that* — update reaches the hook. What the hook does is layered per Decision 3: the composition layer defines it as re-running `build()` (Flutter `StatelessElement.update` semantics); non-component branches define their own artifact response (the Flutter `RenderObjectElement.update` analog).

This deliberately diverges from perception's current behavior, where `update()` swaps the config without re-running component builders (`perception_element.dart` `update()` only assigns `_perception`). Spike 5 surfaced the gap as needing a decision: "config changes to a stateful component are invisible until something else dirties it" (`spike5_action_roundtrip/NOTES.md`, framework feedback). Expression surfaces must re-render on prop change with no manual plumbing, so genesis takes the Flutter rule.

**Why spike 5's proofs survive:** the spike's crux is element-*identity* preservation across whole-tree re-emission — survivors keep `identical()` element instances and live counter state, proven independently of whether builders re-run. Its "re-emission runs zero builders" observation was an artifact of current perception behavior (and an asset for isolating the identity proof), not a property genesis preserves. Identity holds either way; only the rebuild side-effect changes.

**Consequence:** `Branch.update`/`TreeOwner` flush semantics implement the rule; the perception rebuild (Decision 8 campaign) inherits it, so perception tests encoding the old no-rebuild behavior are updated deliberately as part of the cutover.

## Decision 5 — `Branch`/`TreeOwner` API obligations from the spikes *(promotes the A8/A4 API-surface findings folded in the register's spike verdict)*

Two API holes were hit by building real backends against perception; both are obligations on `tree`'s day-one surface (source: `spikes/RESULTS.md` findings ledger):

1. **`TreeOwner`'s flush exposes the drained dirty set to render backends.** `PerceptionOwner`'s dirty set is private, so spike 4 had to fake dirty-region mapping with a builder-driven `RepaintNotifier` — each watched box's builder marking its own box index, a stand-in for render state the owner should have reported (`spike4_tree_terminal/NOTES.md`). The payoff it unlocked is the A4 economics: on a 40×12 grid (480 cells, 1053-byte full redraw), update frames ran 0–38 bytes — ten scripted updates totalled 268 bytes vs 10530 for full redraws, ~39× cheaper, with locality hard-asserted (zero cells changed in static rects; the static element never rebuilt). A flush must hand the backend *what rebuilt*.
2. **`Branch` needs a `visitChildren` traversal API.** No element traversal exists; spikes 4 and 5 walked the live tree by dispatching on concrete element shapes via test-only getters (`NodeElement.children`, `ComponentElement.child`). Spike 5's hit-test gate — resolve `sourceComponentId` to a mounted element by walking the live tree fresh on every route call — is exactly the consumer that needs a real traversal contract.

## Decision 6 — Subclass mechanics: perception extends the tree spine *(promotes A12)*

`Perception extends Seed`; `PerceptionElement extends Branch`; **`PerceptionContext` is a capability extension of `TreeContext`** — the domain layers budget/harvest capabilities onto the handle, which is exactly what Decision 2's separate-handle architecture is for; `PerceptionOwner` builds on `TreeOwner`.

**Consequence, accepted out loud:** perception's public signatures surface tree types. Perception should *be* a tree domain, visibly; lenny ADR 0001's vocabulary maps onto tree types, and the perception rebuild (Decision 8 campaign) implements the mechanics. This resolves the perception/tree type relationship Decision 1 left implicit — "consumer of `tree`" is now concretely "subclass of the tree spine".

## Decision 7 — House conventions: the memento set *(promotes A6)*

genesis adopts the shared memento conventions (dragged from the_grid ADR-0001 D1/D2/D7) so code reads identically across genesis/lenny/the_grid:

- **Workspace:** Dart pub workspace + melos; `build_runner` wired into the melos scripts (consistent with ADR-0002's codegen).
- **Types:** **freezed sealed unions** with `json_serializable` codecs; **exhaustive `switch` expressions as house style**, compiler-checked.
- **Lints:** the shared `analysis_options.yaml` shape — `strict-casts`/`strict-inference`/`strict-raw-types`, `prefer_single_quotes`, `sort_pub_dependencies`, `unawaited_futures`, `avoid_print`.
- **Architecture:** predictable-flutter layering (Services → Repositories → Interactors/Selectors → View) and its testing discipline — **Fakes, not mocks**; state-transition assertions; offline unit tests.

**Not dragged** (domain-specific, stay grid-local): the bd-CLI/Dolt substrate, the convergence reconciler (grid ADR-0003), domain projections over beads (grid ADR-0002), the exploration-protocol observability surface.

**Caveat — Riverpod stays consumer-side:** lenny is on `flutter_riverpod 2.6`, grid on `riverpod 3.0`. genesis's `tree` core is a reconciler **engine** with its own owner/sink — not Riverpod-based — so Riverpod remains a *consumer* choice; any future genesis-level reactive helper must pick a lane or stay Riverpod-agnostic.

## Decision 8 — Bootstrap plan: ADR-first, one campaign, path deps now *(promotes A10)*

1. **ADR-first.** ADRs are drafted from the ADR-0000 register and ratified by Nico *before* implementation. Drafts carry `Status: Proposed`; only Nico flips them to Accepted — the ADR-0000 Rule applied to bootstrap.
2. **One campaign.** `tree` extraction + perception rebuilt on it + lenny cutover proceed as a single sequence, with **perception's existing test suite as the conformance gate** (modulo the deliberate Decision 4 delta). No window with two diverging element cores. Perception is small enough to move whole — 9 source files at `com.nicospencer/lenny/packages/perception/lib/src/` (`perception`, `perception_element`, `perception_context`, `perception_owner`, `stateless_perception`, `stateful_perception`, `inherited_perception`, `node`, `watch`).
3. **Path deps now, git pin at launch.** Consumers wire to genesis via sibling-checkout path dependencies while the `tree` API is hot, switching to git refs/tags at stabilization for the org move + launch.
4. **Scaffolding.** genesis ships the workspace + melos + Decision 7 conventions, a `CLAUDE.md` carrying the ADR-0000 register Rule, and `bd init`.

The gate to start was the spike verdict: all five green, adversarially verified (independent skeptics re-ran every spike fresh; injected bugs flipped every suite red — `spikes/RESULTS.md`). The spike tree is reference-implementation evidence, disposable once genesis lands the real thing.

---

## Alternatives considered

- **Perception (or the_grid) owns the substrate** — rejected (Decision 1): the "one substrate or two?" question answers *neither*; making either consumer the owner couples the engine to one domain's vocabulary and forks the other.
- **`Branch implements TreeContext`** (Flutter's `Element implements BuildContext`, lenny ADR 0001's `PerceptionElement implements PerceptionContext`) — rejected (Decision 2): re-commits the context-leak bug class that spike 5's staleness rejection exists to catch, in a system where agents hold handles across async gaps as a matter of course.
- **A build contract on `Branch` core** (every node builds) — rejected (Decision 3): Flutter's own factoring keeps `Element` agnostic to its two artifact semantics (`ComponentElement` vs `RenderObjectElement`); a core build contract would answer the "overloading genesis" worry by discipline instead of structure.
- **Keep perception's no-rebuild-on-update semantics** — rejected (Decision 4): expression surfaces would need manual dirtying on every prop change; the Flutter rule costs nothing the identity proofs depend on.
- **Keep the dirty set private; backends self-report regions** — rejected (Decision 5): spike 4's builder-driven notifier worked but is a fake — render state belongs with the owner's flush, not in every builder.
- **Typedefs or a wholesale rename instead of subclassing** — rejected (Decision 6): perception should *be* a tree domain, visibly; aliasing would hide the tree types its public signatures deliberately surface.
- **Riverpod-based reactive core** — rejected (Decision 7 caveat): the engine is its own owner/sink; baking in either Riverpod major would force the 2.6/3.0 divergence onto every consumer.
- **Incremental extraction (tree first, perception later)** — rejected (Decision 8): leaves a window with two diverging element cores and no conformance gate on the second.
- **Git/hosted deps from day one** — rejected (Decision 8): sibling path deps are the fastest iteration loop while the `tree` API is hot; pinning happens at stabilization, when it buys reproducibility instead of friction.

## Register provenance

This document promotes the following ADR-0000 register entries, each flipped to `promoted → ADR-0001` at ratification (Nico, 2026-06-11):

- **A1** — Substrate factoring + the two-axis model → Decision 1
- **A8** — Shed the Element≡Context "original sin"; `Seed`/`Branch`/`tree` naming → Decision 2 (and the register spike-verdict API-surface findings → Decision 5)
- **A11** — Layering: `tree` owns structure + composition; artifact semantics are domain-owned → Decision 3
- **A9** — Config update invokes the rebuild hook (reworded at ratification per A11) → Decision 4
- **A12** — Subclass mechanics: perception extends the tree spine → Decision 6
- **A6** — Adopt the memento house conventions → Decision 7
- **A10** — Bootstrap plan: ADR-first, one-campaign extraction, path-dep wiring → Decision 8

Referenced as **pending**, not promoted here: **A13** (Watch lives in `tree`'s composition layer; the expression row stays in genesis) — cited by Decision 3.

Not promoted here: A2 (→ ADR-0002), A3 (→ ADR-0003), A4 (→ ADR-0004), A5 (→ ADR-0005); **A7 stays open in the register** and is promoted by no ADR.
