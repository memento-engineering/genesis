# ADR-0001 — Foundations for genesis

**Status:** Accepted 2026-06-11 (Nico) — ratified from register A1, A6, A8, A9, A10, A11, A12; *amended 2026-06-13 — as-built/placement records A13, A14, A15, A16, A18 promoted from the register; amended 2026-06-14 — `Sprout` (A29) and `StatefulBranch.state` `@protected` (A30) promoted into Decision 3.*
**Date:** 2026-06-11 (amended 2026-06-13)
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

| Package (dir / pubspec) | Contents | When |
|---|---|---|
| `packages/tree` → `genesis_tree` | the engine: `Seed` → `Branch`, `TreeContext`, `TreeOwner`, keyed reconcile | now |
| `packages/perception` → `genesis_perception` | the measurement domain: `Perception`/`PerceptionContext`/`PerceptionOwner`, rebuilt on `tree` | now (migrates from lenny) |
| `packages/taxonomy` → `genesis_taxonomy` | schema → factory registry + LLM tool schema (register A2 → ADR-0002) | now |
| `packages/typesetting` → `genesis_typesetting` | cell/TUI human-facing backend (register A4 → ADR-0004) | now |

**Consequence:** lenny ADRs 0001/0002 (perception design + migration) migrate here when the code moves; perception keeps its domain vocabulary as a consumer of `tree`, that vocabulary mapping onto tree types by subclassing (Decision 6).

**Naming scheme** *(amended 2026-06-13 — promoted from register A16):* directory names stay short (`packages/tree`); the pubspec **package** name carries a `genesis_` prefix (`genesis_tree`, `genesis_perception`, …) so genesis never squats generic pub names. The prefix lives in the pubspec **only** — there are **no `Genesis*` type prefixes**; `Seed`/`Branch`/`Perception` stay unprefixed. Package names are **human faculties, crafts, and achievements — never agent-nouns** (etcher/illuminator/corrector are rejected): `perception`, `expression`, `typesetting`. **Scope clarification (Nico, 2026-06-13): the no-agent-noun rule governs package names only.** Type-level agent-nouns are fine and follow Flutter precedent — `TreeOwner`/`PerceptionOwner` (≅ `BuildOwner`), `TreeContext` (≅ `BuildContext`), `*Binding` (≅ `PipelineOwner`/binding). The two anticipated backends carry their final names: the cell/TUI backend is **`genesis_typesetting`** (the `tree_terminal` working name is retired) and the codegen catalog is **`genesis_taxonomy`** (retiring `tree_codegen`); see ADR-0002/0004.

## Decision 2 — The tree spine: `Seed` → `Branch`; `TreeContext` is a separate handle *(promotes A8)*

**Naming:** **`Seed`** = immutable config (the Widget analogue — planted, describes what grows) → **`Branch`** = mounted, persistent node (the Element analogue) · **`TreeContext`** = the build-time capability handle · **`TreeOwner`** = the scheduler (dirty set + flush) · package **`tree`**.

**The fork — shed Flutter's Element≡BuildContext "original sin":** `Branch` does **not** implement `TreeContext`. The context is a *distinct capability handle* passed to `build()`, never the mounted node itself. Flutter's `Element implements BuildContext` makes every build context a live tree node that can be held past validity or used across an async gap — a bug class Flutter mitigates with `mounted` checks and lints. It matters *more* here than in Flutter, because agents routinely hold handles across async gaps: an agent reads a projection, deliberates for seconds, then acts. lenny ADR 0001 re-committed the sin (`PerceptionElement implements PerceptionContext` — visible today at `packages/perception/lib/src/perception_element.dart`, line 10); genesis deliberately diverges.

**Spike 5 is the executable argument.** Its action router holds no element references at all — the agent's handle is a component *id*, hit-tested fresh against the live tree on every route call. When a v2 re-emission unmounts the target between the agent reading the surface and firing the action, the action rejects as `staleUnmounted` — distinguishable from `unknownComponent` via an ever-seen-id set — and every rejection path leaves the tree byte-for-byte untouched (`spikes/spike5_action_roundtrip/NOTES.md`, test e). "The projection moved under the actor" is first-class and detectable precisely because nothing the actor holds *is* the tree. A context handle that is the `Branch` would re-open that hole from the inside; a separate, invalidatable `TreeContext` closes it by construction.

*(Register note, carried verbatim: the literal "original sin" comment is not present in the installed Flutter SDK at `/Users/nico/flutter` — reworded/removed in that version; the entry records the design fork, not the quote.)*

## Decision 3 — Layering: `tree` owns structure + composition; artifact semantics are domain-owned *(promotes A11)*

**`Branch` core is artifact-agnostic** — identity, lifecycle, keyed reconcile, dirtiness, and **one abstract rebuild hook** (the `performRebuild` analog). It carries **no build contract**. The Flutter precedent is exact: `Element` itself never promises a build — `ComponentElement` (build → child widgets) and `RenderObjectElement` (render artifacts) are two artifact semantics under one tree, and the base class is agnostic to both.

A thin **composition layer** inside `tree` defines the hook as re-running `build()`: the `ComponentBranch` analog (build → child `Seed`s); `Stateless`/`Stateful` + `State` with the neutral setState-analogue; `Inherited`; and `Watch` (register A13). The composition layer ships **experimental under the two-consumer rule** — its API freezes only after `perception` AND one expression surface both consume it.

**`Watch<T>` lives here, in `tree`'s composition layer** *(amended 2026-06-13 — promoted from register A13):* it is pure composition + `dart:async` with zero measurement semantics (a `StatefulSeed` whose state subscribes to a stream and rebuilds on each event — `packages/tree/lib/src/watch.dart`), and it is the Attention primitive of ADR-0005's projection substrate. Flutter ships `StreamBuilder` in the core framework; genesis follows. `perception` consumes it by **re-export** (Decision 6), not subclass. The expression-row packages built on this composition layer (wire/actions/terminal) stay **in the genesis repo** as sibling packages, consistent with Decision 1 (genesis = shared substrate; the_grid consumes) — they do not move to the_grid.

**`Sprout` — the hooks-style stateful primitive** *(amended 2026-06-14 — promoted from register A29):* a `Sprout extends Seed` declares its state inline in `build(SproutContext)` via hooks (`useState` → `StateCell<T>`, `useStream`, `useEffect`, `useMemo`), removing the `StatefulSeed` + separate `State<T>` ceremony for the common case while keeping `State<T>` for complex lifecycles (**additive, not a replacement**; `Watch` likewise stays). The `Sprout` subclass remains the reconcile type-tag (`Seed.canUpdate` keys on `runtimeType` — it cannot be a `createBranch` factory field, nor the shared `Branch` type which is too coarse); state lives on the persistent `SproutBranch` in call-order hook slots, reached only through the A8 `SproutContext` handle. Effects are **microtask-passive** (an effect's `markNeedsRebuild` lands in a fresh flush pass, so it cannot trip `TreeOwner`'s re-dirty assert); rules of hooks — type-drift and both count-drift directions throw, outside-`build` and set-state-during-`build` assert; disposal is reverse-order and per-hook guarded. Ships **experimental under the two-consumer rule** (its only consumer so far is its own tests). As-built detail in register A29.

**`StatefulBranch.state` is `@protected`** *(amended 2026-06-14 — promoted from register A30):* the mutable-`State` accessor (and `genesis_perception`'s `StatefulPerceptionElement.state` override) is **subclass-only, not public API** — external layers must not reach into a branch's `State`. This is what lets the action substrate (ADR-0005) reach actionable components through a narrow seam **on the element** (`branch is Actionable`) rather than reaching a branch's `State`, keeping `tree` **artifact-agnostic** — no action/dispatch vocabulary enters the spine. The rejected alternative — a `useAction`/`ActionHost` hook *in* `tree`/`Sprout` — would have put action semantics in the generic engine.

**Artifact semantics are domain-owned.** Harvest/Observation/Digest/**token budget** (== constraints — Flutter's *render*-tree concern, never Element's) belong to `perception` outright; wire/actions/terminal are sibling expression-row packages that `perception` never imports.

This answers the "overloading genesis" worry structurally rather than by discipline: genesis is a seed/branch tree, full-stop.

**Branch purity invariant** *(amended 2026-06-14 — promoted from register A31):* `Branch` stays exactly **identity + keyed reconciliation + dirtiness**, plus the one abstract `performRebuild` hook with no build contract. It **refuses** the accretion that bloated Flutter's `Element` — no rendering, no gestures/pointers, no `addPostFrameCallback`-shaped lifecycle callbacks, no timers/tickers/listeners on the base. Build, mutable state, effects, and scheduling live in **composition subclasses** (`ComponentBranch`/`StatefulBranch`/`State`/`Sprout`) or **domains**, never on `Branch` — e.g. `Sprout`'s microtask `useEffect` is on `SproutBranch`, never the spine; the action seam is on the element, not in `tree` (ADR-0005 / A30). The one Element-bloat category the base *does* carry — **inherited-value propagation** (`dependOnInheritedSeedOfExactType` + the dependent set) — is a deliberate, bounded port: a pure structural tree-query (not a growing callback registry), load-bearing for providers and render-parent threading (ADR-0004 / A24), and its per-branch cost is **lazy** (the dependent set is allocated only when a branch actually depends on an `InheritedSeed`). The test when extending `Branch`: if the proposed addition is *a callback the framework calls back into*, it belongs in a subclass, not the spine.

## Decision 4 — Config update invokes the rebuild hook *(promotes A9, reworded at ratification per A11)*

When keyed reconcile updates a mounted `Branch` in place (`canUpdate`: same runtimeType + key, new `Seed`), the update **invokes the Branch's rebuild hook** — *unless the new seed is `identical()` to the mounted one* (see the fast-path clause below). `Branch` core fixes only *that* — a non-identical update reaches the hook. What the hook does is layered per Decision 3: the composition layer defines it as re-running `build()` (Flutter `StatelessElement.update` semantics); non-component branches define their own artifact response (the Flutter `RenderObjectElement.update` analog).

**Fast path — "unless identical"** *(amended 2026-06-13 — promoted from register A18, landed `4daada8`):* `Branch.updateChild` and `Branch.updateChildren` **skip the in-place update when `identical(child.seed, newSeed)`** — no `update()`, no force-rebuild, no subtree cascade — porting Flutter's `Element.updateChild` fast path so a `const`-canonicalized or deliberately reused seed prunes its whole subtree at reconcile time. Three genesis refinements: (1) the check is written `identical()` explicitly and **`Seed.operator==` stays unpinned** — free for future freezed value-equality without ever affecting reconcile (Flutter instead forbids overriding `Widget.==`); (2) `updateChildren` delegates each matched pair to `updateChild`, so the skip lives at a single site; (3) `Branch` stores no slot, so there is no slot-update branch yet — a **recorded obligation** for when render branches grow slots (`updateChild`'s doc comment). The skip is reconciliation-only: **`Branch.update` itself keeps its force-rebuild semantics** (a direct `branch.update(sameInstance)` still rebuilds). Provider correctness is independent of the cascade — `InheritedBranch.update` notifies dependents *before* reconciling its child, so a dependent under an identical-skipped subtree still invalidates, lands in the owner dirty set, and rebuilds at drain time (this is the A14 flush inclusion-rule delta recorded in Decision 5). The wire path gains nothing — deserialized A2UI seeds are never `identical()`; wire-cost containment belongs in `genesis_dialogue` (ADR-0003), and a `==`-based skip was considered and rejected.

This deliberately diverges from perception's current behavior, where `update()` swaps the config without re-running component builders (`perception_element.dart` `update()` only assigns `_perception`). Spike 5 surfaced the gap as needing a decision: "config changes to a stateful component are invisible until something else dirties it" (`spike5_action_roundtrip/NOTES.md`, framework feedback). Expression surfaces must re-render on prop change with no manual plumbing, so genesis takes the Flutter rule.

**Why spike 5's proofs survive:** the spike's crux is element-*identity* preservation across whole-tree re-emission — survivors keep `identical()` element instances and live counter state, proven independently of whether builders re-run. Its "re-emission runs zero builders" observation was an artifact of current perception behavior (and an asset for isolating the identity proof), not a property genesis preserves. Identity holds either way; only the rebuild side-effect changes.

**Consequence:** `Branch.update`/`TreeOwner` flush semantics implement the rule; the perception rebuild (Decision 8 campaign) inherits it, so perception tests encoding the old no-rebuild behavior are updated deliberately as part of the cutover.

## Decision 5 — `Branch`/`TreeOwner` API obligations from the spikes *(promotes the A8/A4 API-surface findings folded in the register's spike verdict)*

Two API holes were hit by building real backends against perception; both are obligations on `tree`'s day-one surface (source: `spikes/RESULTS.md` findings ledger):

1. **`TreeOwner`'s flush exposes the drained dirty set to render backends.** `PerceptionOwner`'s dirty set is private, so spike 4 had to fake dirty-region mapping with a builder-driven `RepaintNotifier` — each watched box's builder marking its own box index, a stand-in for render state the owner should have reported (`spike4_tree_terminal/NOTES.md`). The payoff it unlocked is the A4 economics: on a 40×12 grid (480 cells, 1053-byte full redraw), update frames ran 0–38 bytes — ten scripted updates totalled 268 bytes vs 10530 for full redraws, ~39× cheaper, with locality hard-asserted (zero cells changed in static rects; the static element never rebuilt). A flush must hand the backend *what rebuilt*.
2. **`Branch` needs a `visitChildren` traversal API.** No element traversal exists; spikes 4 and 5 walked the live tree by dispatching on concrete element shapes via test-only getters (`NodeElement.children`, `ComponentElement.child`). Spike 5's hit-test gate — resolve `sourceComponentId` to a mounted element by walking the live tree fresh on every route call — is exactly the consumer that needs a real traversal contract.

**As-built `tree` API surface** *(amended 2026-06-13 — promoted from register A14, built `d035c60`, adversarially verified incl. tamper probe):* the two obligations above were discharged, and the extraction settled the rest of the day-one surface:

- **`TreeOwner.flush()` → `List<Branch>`** drains the dirty set depth-ordered (parents before children) and returns the branches *this call* rebuilt, in flush order — the drained dirty set handed to render backends. **Inclusion rule:** a drained branch is included iff it was still mounted and dirty at drain time; a branch force-rebuilt earlier by an update cascade (Decision 4 clears its dirty flag) or unmounted after scheduling is drained but excluded; branches dirtied mid-flush rebuild in the same pass and are included. *Delta from the A18 fast path (landed `4daada8`):* a dependent under an identical-skipped subtree is no longer force-rebuilt by a cascade, so it stays dirty, drains, and is now **included** in the returned list (strictly better render-backend reporting; pinned by `a18_fast_path_test.dart` #5). The cascade-force-rebuild exclusion still holds on the non-identical path.
- **`onNeedsFlush`** fires on the empty→non-empty edge of the dirty set — exactly once when work first becomes available, again only after a `flush()` drains the set.
- **`State.setState(fn)`** keeps the Flutter name (perception aliases it `perceived()`); `State`'s config getter is **`seed`**; `State.context` returns the separate handle, never the branch.
- **`visitChildren(visitor)`** is shallow (direct children, tree order); the base visits nothing; callers recurse; the tree must not be mutated during a visit.
- **`TreeContext`** = `mounted` (the staleness probe — **never throws**) + `key`/`branchId`/`dependOnInheritedSeedOfExactType<T>()`/`markNeedsRebuild()`, all throwing `StateError` after unmount (Decision 2, executable). The canonical handle is created lazily once per branch via `Branch.context`; **`Branch` does NOT implement `TreeContext`** (the Decision 2 fork, structurally enforced).
- **A9 mechanics** (Decision 4): `update(newSeed)` = assert `canUpdate` → swap seed → `rebuild(force: true)`; the dirty flag clears *before* the hook so a force-rebuilt branch is not double-built in the same flush. `InheritedBranch.update` notifies dependents *before* reconciling its child (Flutter ProxyElement order — keeps builds == 1 per provider update).
- **`branchId`** is an owner-scoped monotonic decimal string, assigned once at mount (ported verbatim).
- **`Node`/`NodeElement` are NOT `tree` lib code** — they live only as a **test fixture** (Decision 3: core is artifact-agnostic; the container artifact lives in `perception`). The fixture is the canonical non-component-branch example.

## Decision 6 — Subclass mechanics: perception extends the tree spine *(promotes A12)*

`Perception extends Seed`; `PerceptionElement extends Branch`; **`PerceptionContext` is a capability extension of `TreeContext`** — the domain layers budget/harvest capabilities onto the handle, which is exactly what Decision 2's separate-handle architecture is for; `PerceptionOwner` builds on `TreeOwner`.

**Consequence, accepted out loud:** perception's public signatures surface tree types. Perception should *be* a tree domain, visibly; lenny ADR 0001's vocabulary maps onto tree types, and the perception rebuild (Decision 8 campaign) implements the mechanics. This resolves the perception/tree type relationship Decision 1 left implicit — "consumer of `tree`" is now concretely "subclass of the tree spine".

**As-built perception↔tree mapping** *(amended 2026-06-13 — promoted from register A15; rebuilt `4da3378`, conformance gate 104/104 with deltas ledgered in `docs/CONFORMANCE-DELTA.md`):*

- **`Perception extends Seed` keeps `createElement()`** as the domain factory name; `createBranch()` is a one-line bridge to it, so the tree reconciler mounts perceptions like any other `Seed`.
- **`markNeedsHarvest` is the single domain override point.** Tree-core invalidation (`markNeedsRebuild`, e.g. a provider's `dependencyChanged`) **funnels through it**; it super-calls the tree path (no recursion). Routing invalidation through the domain name is what kept lenny's invalidation tests valid verbatim.
- **`PerceptionContext implements TreeContext`** via a private wrapper over the canonical tree handle (handle layering — inherits throw-after-unmount for free); it adds `perceptionId` + `markNeedsHarvest`, and is documented as the seam where the token budget capability lands (Decision 3).
- **`PerceptionOwner extends TreeOwner`**; `flushHarvest()` now *returns* the rebuilt list (was void in lenny), aliasing `flush()`.
- **The load-bearing call: composition elements are NOT `PerceptionElement`s.** The stateless/stateful/inherited perception elements are thin subclasses of the *tree* composition branches (`StatelessBranch`/`StatefulBranch`/`InheritedBranch`) that only upgrade the handle to `PerceptionContext`. `PerceptionElement extends Branch` is **reserved for artifact elements** — `NodeElement`, `FieldElement`, custom measurement leaves — mirroring Flutter's `ComponentElement` vs `RenderObjectElement` split. (Composition is tree-owned, artifact semantics domain-owned — Decision 3, made literal in the type hierarchy.)
- **`Node`** is ported as a `Perception` with children widened to `List<Seed>` (so a measurement freely mixes artifact leaves with composition configs); **`Field(String name, Object? value)`** is added as the leaf — **non-generic on purpose**: a `Field<T>` would break `canUpdate` across value-type changes, and `null` is a legal measurement.
- **`Watch` is re-exported from `tree`, not subclassed** (Decision 3 / register A13); the perception barrel re-exports `tree` in full, so one import surfaces the spine + the domain — the practical form of this Decision's "public signatures surface tree types".

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

This document promotes the following ADR-0000 register entries. The first round flipped to `promoted → ADR-0001` at ratification (Nico, 2026-06-11):

- **A1** — Substrate factoring + the two-axis model → Decision 1
- **A8** — Shed the Element≡Context "original sin"; `Seed`/`Branch`/`tree` naming → Decision 2 (and the register spike-verdict API-surface findings → Decision 5)
- **A11** — Layering: `tree` owns structure + composition; artifact semantics are domain-owned → Decision 3
- **A9** — Config update invokes the rebuild hook (reworded at ratification per A11) → Decision 4
- **A12** — Subclass mechanics: perception extends the tree spine → Decision 6
- **A6** — Adopt the memento house conventions → Decision 7
- **A10** — Bootstrap plan: ADR-first, one-campaign extraction, path-dep wiring → Decision 8

The second round — as-built/placement records ratified by Nico 2026-06-13 — was folded in by the promotion pass (amendment notes dated 2026-06-13 mark each insertion):

- **A16** — Package naming scheme (`genesis_` pubspec prefix; no `Genesis*` type prefixes; short dirs; no-agent-noun *package* names, with the 2026-06-13 scope clarification that type-level agent-nouns are fine) → Decision 1 (naming scheme).
- **A14** — As-built `tree` API surface (`flush()` inclusion rule + `onNeedsFlush`; `setState`/`seed`; `visitChildren`; `TreeContext` members + throw-after-unmount; A9 mechanics; `branchId`; `Node`-as-test-fixture) → Decision 5 (and the A9 mechanics reinforce Decision 4).
- **A18** — Identical-config fast path (`identical(child.seed, newSeed)` skip; `Seed.==` unpinned; `Branch.update` keeps force semantics; the flush inclusion-rule delta), landed `4daada8` → Decision 4 ("unless identical" clause) + Decision 5 (inclusion-rule delta).
- **A15** — As-built perception↔tree mapping (`createElement` kept; `markNeedsHarvest` funnel; `PerceptionContext implements TreeContext`; `PerceptionOwner extends TreeOwner`; the load-bearing call — composition elements are tree branches, not `PerceptionElement`s; `Field(name, value)` non-generic; `Watch` re-exported) → Decision 6.

The third round — promoted by the pass dated 2026-06-14:

- **A29** — `Sprout`, the hooks-style stateful primitive (`useState`/`useStream`/`useEffect`/`useMemo`; `StateCell<T>`; microtask-passive effects; rules of hooks; reverse-order guarded disposal), additive beside `State<T>`/`Watch` → Decision 3.
- **A30** — `StatefulBranch.state` (and perception's override) made `@protected` so the action seam lives on the element and `tree` stays artifact-agnostic → Decision 3. *(A30's consent half — the element `Actionable` seam — lands in ADR-0005.)*
- **A13** — Watch lives in `tree`'s composition layer; the expression row stays in genesis → Decision 3 (no longer pending; the ADR-0003/0005 repo-placement note is promoted there).

Not promoted here: A2 (→ ADR-0002), A3 (→ ADR-0003), A4 (→ ADR-0004), A5 (→ ADR-0005); A17 (roadmap package names → ADR-0002/0003/0005), A19/A24 (taxonomy/typesetting as-built → ADR-0002/0004); **A7 stays open in the register** and is promoted by no ADR.
