# ADR-0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (adopted from the_grid ADR-0000, Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR-0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects · **Status:** pending | promoted → ⟨where⟩ | rejected.

**Repo position:** `genesis` is the shared substrate — the node/element/keyed-reconcile engine extracted from Flutter (package **`tree`**) plus the perception domain built on it (package **`perception`**). Consumers: `com.nicospencer/lenny` (testing harness, via `perception`) and `engineering.memento/the_grid` (platform SDK). Entries A2–A5 were migrated from lenny's register on 2026-06-11 when this repo was created; A6 was dragged from the_grid. Origin is noted per entry.

**Spike verdict (2026-06-11):** all five de-risking spikes (lenny beads `lenny-dtcv/17qo/f5zn/vu1j/78r1`) ran **green with adversarial verification** — evidence consolidated at `com.nicospencer/lenny/spikes/RESULTS.md` (untracked) and per-spike `NOTES.md`. A2/A3/A4/A5 now carry executable evidence; spike findings to fold in on promotion: A2UI **v0.9 renamed `surfaceUpdate` → `updateComponents`** (A3); `TreeOwner` must expose the drained dirty set to render backends, and `Branch` needs `visitChildren` (A4/A8 API surface); codegen needs plugin-key/provenance/registry-parameterization seams (A2).

---

## A1 (2026-06-11) — Substrate factoring + the two-axis model  ·  decider: Nico

**Decision:** `genesis` is the shared engine; `perception` and `the_grid` are domain **consumers**, not owners of the substrate. Repo `memento-engineering/genesis` houses package **`tree`** (the engine — `Seed` config → `Branch` mounted, with `TreeContext` a *separate* handle + `TreeOwner` scheduler — A8, decided 2026-06-11) and package **`perception`** (`Perception`/`PerceptionContext`/`PerceptionOwner`, the measurement domain). Two orthogonal axes govern every projection: **authoring** = measurement (read-only) / expression (read-write); **rendering** = model-facing (serialize, no geometry) / machine-facing (typed structs) / human-facing (render tree, 2-D geometry).
**Why:** resolves the perception↔grid "one substrate or two?" question — neither; genesis is the root both build on. The two axes dissolve the apparent conflicts in A3 and A4: each is a different cell of the 2-axis space, and lenny's ADR 0001 occupied exactly one cell (measurement + model-facing), correctly.
**Affects (if promoted):** seed of a genesis ADR-0001 (foundations); repo/package layout; lenny ADR 0001/0002 (perception) migrate here when the code moves.
**Origin:** lenny conversation 2026-06-11. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A2 (2026-06-11) — Node vocabulary is schema-first + codegen; `dart:mirrors` dropped  ·  decider: Nico

*(migrated from lenny A1)*
**Decision:** the `tree`/`perception` node catalog is defined as **schemas**; **codegen** emits the Dart factory registry + per-node JSON/tool schemas. No `dart:mirrors` anywhere; runs unchanged on every Dart target (VM, AOT, web).
**Why:** mirrors are unavailable under Flutter/AOT and semi-abandoned; macros cancelled. A codegen'd registry is the only path uniform across all Dart targets that stays tree-shakeable. One schema is simultaneously the Dart factory registry and the LLM tool/JSON schema.
**Affects:** a `tree_codegen` (or build_runner config); the extension-contract registration (lenny register A1); the conventions baseline (A6). **Status:** promoted → ADR-0002 (ratified Nico 2026-06-11).

## A3 (2026-06-11) — A2UI flat-keyed grammar as the bidirectional wire format — *scoped to the authoring axis*  ·  AI

*(migrated from lenny A2; rescoped + retagged scoped)*
**Decision:** adopt Google **A2UI** (v0.9) flat-list-with-stable-IDs model (`surfaceUpdate`/`dataModelUpdate`/`action`) as both the serialization and the emission grammar; `tree` keys == A2UI component IDs; whole-(sub)tree emission reconciles to a patch by key (no "whole tree vs patch" fork).
**Scope (resolves the apparent 0001 conflict):** authoring is a property of the tree's *role*, not the engine. **Measurement** trees stay read-only — lenny ADR 0001's "the model never constructs Perceptions" is the *integrity rule of a measurement*: the model's only `put` is a hit-tested action on the world, after which the tree re-measures. **Expression** trees (surfaces) are authored directly. genesis supports both; A2UI authoring lives on the expression row, leaving 0001 intact for perception.
**Why:** A2UI is purpose-built for LLM incremental/streamed generation, is a framework-agnostic standard (`genui`/web/Angular), and maps onto genesis keyed reconciliation. Scoping by authoring-role bounds the "revisits 0001" tension rather than overturning it.
**Affects:** lenny ADR 0001's bespoke Observation JSON (now the measurement+model-facing cell); a serializer + a deserialize/reconcile path in `tree`. **Status:** promoted → ADR-0003 (ratified Nico 2026-06-11; v0.9 `updateComponents` vocabulary adopted; fidelity-ledger practice accepted by Nico).

## A4 (2026-06-11) — One tree, multiple render backends; "the window is an embedder choice" — *scoped to the rendering axis*  ·  AI

*(migrated from lenny A3; rescoped + overlap correction + retagged scoped)*
**Decision:** `tree` carries render backends beyond serialization: (a) a pure-Dart **cell/TUI backend** (character grid → ANSI; bare VM, no engine); (b) a **Flutter adapter** (windowed GUI); (c) **headless real Flutter** (`flutter_tester`) as a **conformance oracle only**, never a render path. A window is a property of the chosen embedder, not the framework.
**Scope (resolves the apparent 0001 conflict):** 0001 rejected a retained render tree *for the model-facing projection* — correct: JSON needs hierarchy + size (1-D), not geometry. A render tree is required only for **human-facing** backends (2-D cell/pixel geometry). Orthogonal backends off one element tree; no contradiction. **Sleeper win:** measurement + human-facing = a read-only TUI of the live Observation (lenny's inspector, reborn native-terminal).
**Overlap correction (vs the_grid):** grid's tmux runtime (ADR-0004) is process/session *supervision* (owns terminal real estate); a genesis cell backend *draws into* that real estate — complementary, not duplicative. grid's reconciler (ADR-0003) is a *convergence state machine over beads*; genesis's reconciler is the *tree keyed diff* — two reconcilers at two layers. The earlier "overlap" was **vocabulary collision**, which this factoring disambiguates.
**Why:** enables the agent↔human projection on the bare VM without Skia; the oracle proves the cell backend's layout matches Flutter's instead of asserting it.
**Affects:** package layout (a `tree_terminal`); lenny ADR 0001's render-tree rejection (now scoped to model-facing). **Status:** promoted → ADR-0004 (ratified Nico 2026-06-11).

## A5 (2026-06-11) — The projection/manipulation substrate: four dynamics, four audiences, enforce/reject  ·  AI (consensus lean: Nico)

*(migrated from lenny A4)*
**Decision:** frame the system as *interfaces-as-projections* (`get` projection + `put` handles). Four dynamics, bound to lenny ADR 0001 vocabulary: **Context** = the projection; **Attention** = the subscription graph (`Watch`) + the parked focus-policy knob; **Affordance** = 0001's parked "action/affordance half"; **Intent** = the thing the framework does not supply (model/human/code brings it). **Validation/invalidation = enforce/reject = 0001's "action validation == hit-testing."** Four audiences — human/agent/machine/self — differ only on *who supplies Intent* and *how Context renders* (the A1 rendering axis); **agent→machine is the tool-call projection.** Multi-party consensus on a rejected write is **parked, leaning `setState`** (last-write-wins / silent invalidate).
**Why:** names what 0001 §3 half-formalized and parked, and generalizes single-app-observe → multi-party substrate. Consensus is the genuinely novel surface, deferred until the spikes inform it.
**Affects:** unparks lenny ADR 0001 §3; reconcile vocabulary with the_grid ADR-0002 "reactive domain projections" (same concept over beads). **Status:** promoted → ADR-0005 (ratified Nico 2026-06-11); multi-party consensus NOT promoted — stays parked, lean last-write-wins.

## A6 (2026-06-11) — Adopt the memento house conventions  ·  decider: Nico, via the_grid

*(dragged from the_grid ADR-0001 D1/D2/D7 — the genesis-applicable subset)*
**Decision:** genesis adopts the shared memento conventions so code reads identically across genesis/lenny/the_grid: Dart pub workspace + melos; **freezed sealed unions** with `json_serializable` codecs and **exhaustive `switch` as house style**; `build_runner` wired into melos (consistent with A2's codegen); the `analysis_options.yaml` lint shape (strict-casts/inference/raw-types, prefer_single_quotes, sort_pub_dependencies, unawaited_futures, avoid_print); **predictable-flutter layering** (Services → Repositories → Interactors/Selectors → View) and its testing discipline (Fakes-not-mocks, state-transition assertions, offline unit tests).
**Not dragged** (domain-specific — stay grid-local): the bd-CLI/Dolt substrate (grid ADR-0001 D4), the convergence reconciler (ADR-0003), domain projections over beads (ADR-0002), the exploration-protocol observability surface (D6).
**Caveat — Riverpod version divergence is now a shared concern:** lenny is on `flutter_riverpod 2.6`, grid on `riverpod 3.0`. genesis's `tree` core is a reconciler **engine** (its own owner/sink, not Riverpod-based), so Riverpod stays a *consumer* choice; any genesis-level reactive helper must pick a lane or stay Riverpod-agnostic.
**Affects:** genesis `pubspec.yaml`/`melos.yaml`/`analysis_options.yaml` when scaffolded; a genesis `CLAUDE.md` (onboarding, grid ADR-0001 D8). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A7 (2026-06-11) — Open: grid's structural snapshot-diff vs genesis keyed reconcile  ·  AI (flag, not a decision)

**Recorded as an open relationship, not resolved:** the_grid (ADR-0001 D5) detects change by **structural diff of whole snapshots** (`diffSnapshots`) because beads are not a keyed element tree; genesis reconciles by **key/identity** (lenny ADR 0001's core move — "reconcile by identity, not structural diff"). Open question: does grid eventually mount its bead domains as genesis `tree` nodes (inheriting keyed reconcile + the A5 projection mechanism), or keep structural diffing as a separate layer? Recorded so the divergence isn't silently inherited.
**Affects (if resolved):** the_grid ADR-0001 D5 / ADR-0002; whether grid becomes a genesis consumer *in fact* or only in convention. **Status:** pending (open).

## A8 (2026-06-11) — Shed the Element≡Context "original sin"; `Seed`/`Branch`/`tree` naming  ·  decided: Nico

**Decision (Nico, 2026-06-11) — shed the sin:** the mounted node does **not** implement the build context. `TreeContext` is a **distinct capability handle** passed to `build()`, never the `Branch` itself — sheds Flutter's context-leak bug class (held past validity / used across async gaps), which matters *more* here than in Flutter because agents routinely hold handles across async gaps. Diverges deliberately from lenny ADR 0001's `PerceptionElement implements PerceptionContext` (which re-committed Flutter's `Element implements BuildContext`).
**Naming (decided):** **`Seed`** = immutable config (Widget analogue — "planted, describes what grows") → **`Branch`** = mounted, persistent node (Element analogue); **`TreeContext`** = the separate handle; **`TreeOwner`** = scheduler; package **`tree`**.
*(The literal "original sin" comment is not present in the installed Flutter SDK `/Users/nico/flutter` — reworded/removed in this version; this entry records the design fork, not the quote.)*
**Affects:** `tree` base-type API; genesis sheds Flutter's context-leak class of bug. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A9 (2026-06-11) — Config update re-runs the builder (Flutter-style rebuild rule)  ·  decider: Nico

**Decision (reworded 2026-06-11 post-discussion, A11):** in genesis `tree`, when keyed reconcile updates a mounted `Branch` in place (canUpdate: same runtimeType + key, new `Seed`), the update **invokes the Branch's rebuild hook**. `Branch` core fixes only *that* update reaches the hook; the composition layer (A11) defines the hook as re-running `build()` (Flutter `StatelessElement.update` semantics), while non-component branches define their own artifact response (Flutter `RenderObjectElement.update` analog). Diverges deliberately from perception's current behavior (update swaps config without re-running component builders), which spike 5 surfaced as needing a decision.
**Why:** expression surfaces must re-render on prop change with no manual plumbing; element-identity preservation (the A3 crux) holds either way, so spike 5's proofs are unaffected. Chosen by Nico from the post-spike decision set.
**Affects:** `Branch.update`/`TreeOwner` flush semantics; the perception rebuild (A10 campaign) inherits the rule. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A10 (2026-06-11) — Bootstrap plan: ADR-first, one-campaign extraction, path-dep wiring  ·  decider: Nico

**Decision:** (a) **ADR-first** — ADRs are drafted from this register and ratified by Nico *before* implementation; drafts carry Status: Proposed and only Nico flips them to Accepted (the Rule, applied to bootstrap). (b) **One campaign** — `tree` extraction + perception rebuilt on it + lenny cutover proceed as a single sequence; perception's existing test suite is the conformance gate; no window with two diverging element cores. (c) **Path deps now, git pin at launch** — consumers wire to genesis via sibling-checkout path dependencies during development, switching to git refs/tags at stabilization for the org move + launch.
**Why:** the spike verdict (all five green, adversarially verified) gates the start; perception is small enough (9 src files) to move whole; sibling path deps give the fastest iteration while the `tree` API is hot.
**Affects:** bootstrap phases 0–3; lenny `pubspec.yaml` wiring at cutover; genesis repo scaffolding (workspace + melos + A6 conventions + CLAUDE.md carrying this register's Rule + `bd init`). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A11 (2026-06-11) — Layering: `tree` owns structure + composition; artifact semantics are domain-owned  ·  decider: Nico

**Decision:** `Branch` core is **artifact-agnostic** — identity, lifecycle, keyed reconcile, dirtiness, and one abstract rebuild hook (`performRebuild` analog); it carries NO build contract. A thin **composition layer** inside `tree` (ComponentBranch analog: build → child `Seed`s; `Stateless`/`Stateful` + `State` with the neutral setState-analogue; `Inherited`) defines hook = re-run build, and ships **experimental under the two-consumer rule** — its API freezes only after `perception` AND one expression surface both consume it. All artifact/meaning semantics live in domains: harvest/Observation/Digest/**token budget** (== constraints — Flutter's *render*-tree concern, never Element's) belong to `perception` outright; wire/actions/terminal are sibling expression-row packages `perception` never imports.
**Why:** mirrors Flutter's own factoring (Element vs ComponentElement vs RenderObjectElement — two artifact semantics under one tree, base class agnostic to both); answers the "overloading genesis" worry structurally rather than by discipline. From the 2026-06-11 ratification discussion ("genesis is a seed/branch tree, full-stop").
**Affects:** ADR-0001 Decisions 2–4 (reworked at ratification); `tree` package layout; A9's wording (reworded above). **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A12 (2026-06-11) — Subclass mechanics: perception extends the tree spine  ·  decider: Nico

**Decision:** `Perception extends Seed`; `PerceptionElement extends Branch`; **`PerceptionContext` is a capability extension of `TreeContext`** (the domain layers budget/harvest capabilities onto the handle — handle layering is what A8's separate-handle architecture is for); `PerceptionOwner` builds on `TreeOwner`. Consequence accepted out loud: perception's public signatures surface tree types.
**Why:** Nico's call ("subclass") from the 2026-06-11 ratification discussion; typedefs/wholesale-rename rejected — perception should *be* a tree domain, visibly.
**Affects:** the perception rebuild (A10 campaign); lenny ADR 0001 vocabulary maps onto tree types. **Status:** promoted → ADR-0001 (ratified Nico 2026-06-11).

## A13 (2026-06-11) — Watch lives in tree's composition layer; the expression row stays in genesis  ·  AI

**Decision (defaults presented in the 2026-06-11 discussion, unobjected):** `Watch<T>` (stream → rebuild) moves to `tree`'s composition layer — it is pure composition + dart:async with zero measurement semantics, and it is A5's Attention primitive (substrate). `perception` re-exports/subclasses it. The expression-row packages (wire/actions/terminal, future) stay **in the genesis repo** as sibling packages, consistent with ratified A1 (genesis = shared substrate; the_grid consumes) — not in the_grid.
**Why:** Flutter ships StreamBuilder in the core framework; moving the expression row to the_grid would contradict ratified A1.
**Affects:** `tree` composition-layer contents; ADR-0003/0005 repo placement. **Status:** pending.

## A14 (2026-06-11) — `tree` API surface decisions from the extraction build  ·  AI

**Decision (as built, commit `d035c60`; adversarially verified incl. tamper probe):**
- **`TreeOwner.flush()` → `List<Branch>`** — drains depth-ordered, returns the branches *this call* rebuilt; inclusion rule: drained ∧ mounted ∧ still-dirty at drain time (A9-cascade force-rebuilds and unmounted stragglers excluded). `onNeedsFlush` fires on the empty→non-empty edge.
- **`State.setState(fn)`** keeps the Flutter name (perception aliases `perceived()`); State's config getter is **`seed`**.
- **`visitChildren(visitor)`** — shallow, direct children, tree order; base visits nothing; callers recurse; no mutation during visit.
- **`TreeContext`** = `mounted` (never throws — the staleness probe) + `key`/`branchId`/`dependOnInheritedSeedOfExactType<T>()`/`markNeedsRebuild()`, all throwing `StateError` after unmount (A8, executable). Canonical handle lazily created once per branch via `Branch.context`; `Branch` does NOT implement it.
- **A9 mechanics:** `update(newSeed)` = assert canUpdate → swap seed → `rebuild(force: true)`; dirty flag cleared *before* the hook so a force-rebuilt branch isn't double-built in the same flush. `InheritedBranch.update` notifies dependents BEFORE reconciling its child (Flutter ProxyElement order — keeps builds==1 per provider update).
- **`branchId`**: owner-scoped monotonic decimal string, assigned once at mount (ported verbatim).
- **Node/NodeBranch are NOT lib code** — test fixture only (A11: core is artifact-agnostic); the container artifact lives in `perception`.
- **Flagged, not added:** Flutter's identical-config fast path (`identical(seed, newSeed) → skip`) was deliberately not ported; under A9 every in-place update cascades a subtree rebuild — the const-Seed/short-circuit pruning is the natural next optimization decision.
**Affects:** every `tree` consumer; the fast-path question is a future entry. **Status:** pending.

## A15 (2026-06-11) — perception↔tree domain mapping decisions from the rebuild  ·  AI

**Decision (as built, commit `4da3378`; conformance gate 104/104 with deltas ledgered in `docs/CONFORMANCE-DELTA.md`):**
- `Perception extends Seed` keeps **`createElement()`** as the domain factory; `createBranch()` is a one-line bridge.
- **`markNeedsHarvest` is the domain override point**: `markNeedsRebuild()` funnels into it; it super-calls the tree path (no recursion) — provider invalidation flows through the domain name, which is what kept lenny's invalidation tests valid verbatim.
- **`PerceptionContext implements TreeContext`** via a private wrapper over the canonical tree handle (handle layering; inherits throw-after-unmount for free); adds `perceptionId` + `markNeedsHarvest`; documented as the seam where token budget lands.
- **`PerceptionOwner extends TreeOwner`**; `flushHarvest()` now *returns* the rebuilt list (was void in lenny); `scheduleHarvestFor` dropped (nothing called it).
- **The load-bearing call: composition elements are NOT `PerceptionElement`s.** Stateless/Stateful/Inherited perception elements are thin subclasses of the *tree* branches that only upgrade the handle to `PerceptionContext`; `PerceptionElement extends Branch` is reserved for artifact elements (NodeElement, FieldElement, custom measurement leaves) — mirroring Flutter's ComponentElement vs RenderObjectElement split.
- `Node` ported as a Perception with children widened to `List<Seed>` (mixes artifact leaves with composition configs); **`Field(String name, Object? value)`** added — non-generic on purpose (a `Field<T>` would break canUpdate across value-type changes; null is a legal measurement).
- `Watch` **re-exported from tree, not subclassed** (A13); the perception barrel re-exports tree in full — one import surfaces the spine + domain (the practical form of A12's consequence).
- `build(covariant PerceptionContext)` returns `Seed` (widened so builders can return composition seeds).
**Affects:** lenny's future perception consumers; the budget capability lands on `PerceptionContext`. **Status:** pending.
