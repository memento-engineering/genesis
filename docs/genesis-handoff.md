# genesis — handoff (2026-06-14)

Rolling one-file pickup for a fresh **genesis-rooted** session. The original
`taxonomy → dialogue → consent` arc is **complete**: the expression-row
substrate is built end-to-end and one render backend exists. **Active
direction (Nico, 2026-06-14):** pre-publish tidy toward a public release, with a
close look at **`tree`** — optimization and reducing the Flutter-style
`Stateless`/`Stateful`/`State` boilerplate trap before it freezes under the
two-consumer rule.

## What just landed (this session — `genesis_consent`, bead `genesis-hjj`)

The enforce/reject action router (ADR-0005): action validation IS hit-testing
the live tree. dialogue *decodes* a client action into an `ActionEvent` (parse
only); consent *routes* it through three gates (exists/mounted ·
catalog-declared · payload), enforcing valid intents through the target state
and refusing invalid ones with a structured, side-effect-free outcome.

- `ConsentRouter{surface, catalog}` — front door + emission ledger (ever-seen
  ids + id→type); walks the live tree fresh per call (A8).
- `ConsentOutcome = Applied{change} | Rejected{kind, message}` (sealed); four
  `RejectionKind`s; `staleUnmounted` is the A8 agent-async-gap bridge.
- `Actionable{validateAction (pure) / applyAction (enforce via perceived())}` —
  pure-validate-then-mutate makes `badPayload` byte-for-byte untouched by
  construction.
- **No `a2ui_core` dependency** (register A27): it has no element tree to
  hit-test against and no unmount lifecycle, so this layer is genesis-native.

Commits `5a2552c` (feat) + `3b11831` (docs) on `main`. 16 tests; two-skeptic
adversarial verification + 3 tamper probes; M1 (DAG-shared id) hardened to a
loud `StateError`. Workspace green: tree 120 / perception 104 / taxonomy 73 /
typesetting 25 / dialogue 35 / consent 16.

## The stack, as it stands (6 packages, all pure-Dart, bare-VM)

| Package | Role | As-built register |
|---|---|---|
| `tree` | Seed/Branch/keyed-reconcile engine | A8/A9/A11/A12/A14/A18 (promoted) |
| `perception` | measurement domain on the spine | A15 (promoted) |
| `taxonomy` | catalog → registry + tool-schema codegen | A19 (promoted) |
| `typesetting` | bare-VM cell/ANSI render backend | A24 (promoted) |
| `dialogue` | A2UI v0.9 wire (codec + surface + action parse) | A25 (**pending**) |
| `consent` | enforce/reject action router | A28 (**pending**) |

## ACTIVE: pre-publish + the `tree` ergonomics/optimization review

The release-blocking thread. Two parts:

1. **`tree` ergonomics — the `Stateless`/`Stateful`/`State` boilerplate trap.**
   The composition layer (`StatefulSeed` + `createState()` + a separate
   `State<T>` class + `createBranch()`) is ported straight from Flutter and
   carries Flutter's ceremony. genesis is pre-1.0 and the composition layer is
   **EXPERIMENTAL under the two-consumer rule (ADR-0001 D3)** — it freezes only
   after perception AND one expression surface both consume it, so this is the
   moment to cut boilerplate before it sets. Open question to evaluate: can a
   stateful component be expressed without the three-type dance (e.g. a closure-
   /hook-style state, a single-type fused seed+state, or a lighter `setState`
   surface) **without** giving up the A8 separate-handle guarantee or keyed
   reconcile? Files: `packages/tree/lib/src/{stateful,stateless,component_branch,
   inherited,watch}.dart`; the perception faces in `packages/perception/lib/src/
   {stateful_perception,stateless_perception}.dart`.
2. **`tree` optimization.** A18 (identical-skip fast path) is already in. Next
   candidates worth measuring before publish: the depth-ordered flush set, the
   `dependOnInheritedSeedOfExactType` parent-walk (now has two structural
   consumers — providers + render-parent threading), and allocation in
   `updateChildren`.

Any API change here is an AI decision → record as a pending `A<n>` and gate on
all six packages staying green (perception's 104-test conformance suite is the
guard that the spine still behaves).

## "What's left before public publish" — the tidy checklist

- **Promotion pass:** Nico ratifies A25–A28 into ADR-0002/0003/0005 (pending
  register entries should not ship as "decided" while still pending).
- **`tree` ergonomics/optimization** (above) — the one thing to settle *before*
  the experimental composition API freezes.
- **Package metadata for pub:** real `description`s, `repository`/`homepage`,
  `version`s, `LICENSE` per package, top-level `README`s; today pubspecs are
  `publish_to: none` with `any` path-style deps (ADR-0001 D8: switch to
  git refs/tags at stabilization).
- **A2 flagged limits still open:** taxonomy's string-prop/required-only limits
  for typed PROPS; real Dart-enum mapping (ledgered in taxonomy README).
- **Honest deferral ledger:** dialogue's reverse-emission / `updateDataModel` /
  `createSurface` / streaming (A25); `genesis_expression` not built; the agent
  loop not built — decide which are publish-blocking vs post-1.0.
- **A26 interop posture for the public:** position genesis as the framework-
  agnostic A2UI substrate; the cheap a2ui_core conformance test (item 1) is a
  good public credibility signal.

## Open flags from A28 (each wants its own decision/bead)

1. **`tree`: a first-class branch-level action-dispatch hook.** consent reaches
   the target `State` via `StatefulBranch.state` (a getter tree doc-marks
   "do not use in production"). Spike 5 flagged this; it now concretely needs a
   blessed seam — and it overlaps the ergonomics review above.
2. **`taxonomy`: a generated affordance map** (`componentActions`) vs consent's
   runtime `Catalog.parse(...).actions` lookup (ADR-0005 references the spike's
   generated `actions.g.dart`; taxonomy never carried it forward).
3. **`consent`: the DAG-shared-id semantic** — currently a `StateError`
   (authoring error). Keep, or give it a structured actor-facing rejection?
- **A7** still open: does the_grid mount its bead domains as genesis tree nodes?

## Deferred / not-yet-built

- **dialogue (A25):** reverse-emission (Seed-tree → envelope; needs a taxonomy
  reverse-describer); `updateDataModel`/data-binding (adopt a2ui_core's
  `DataModel` post-stable); `createSurface`/`deleteSurface`; streaming.
- **render:** `genesis_expression` (Flutter/`dart:ui` backend, ADR-0004) — not
  built; typesetting is the only backend today.
- **the agent loop** (the capstone) — close model↔genesis end-to-end (author via
  taxonomy schema → receive via dialogue → render via typesetting → enforce via
  consent), adopting `genai_primitives` for the tool/chat vocabulary (A26
  item 4). The natural post-tidy build.

## Orient (read these first, whatever the direction)

- `docs/adr/ADR-0000-ai-decision-register.md` — **THE REGISTER RULE** + entries
  A25–A28 (pending) and the flags above.
- `docs/adr/ADR-0001..0005` — ratified foundations / codegen / wire / render /
  projection-action. ADR-0001 D3 (composition layer experimental) is the key
  one for the tree-ergonomics review.
- `docs/design/community-overlap-genui.md` (A26) + `community-overlap-consent.md`
  (A27) — interop landscape; **interoperate, don't fork**.
- `CLAUDE.md` — conventions (A6 house style; A16 naming; A21 "extension" not
  "plugin"; A22 tests consume `genesis_perception` `Node`/`Field`).
- `packages/consent/README.md` — the freshest worked example of the build style.

## Build discipline

Spike/seam-first → build against the as-built packages → adversarially verify
(repro + design/fidelity skeptics, tamper probes that must each trip a distinct
test) → gate on the whole workspace staying green → record as-built API
decisions as a pending `A<n>` register entry (Nico promotes). Pure-Dart,
bare-VM; no "plugin" wording; tests use perception `Node`/`Field`. Land
direct-to-main with logical commits + `Co-Authored-By` trailer; **confirm before
pushing** (the push is the one step that needs explicit go-ahead).

## Recall prompt (paste to start)

> Read `docs/genesis-handoff.md` and the docs it links. The active direction is
> pre-publish tidy + a `tree` optimization/ergonomics review (cutting the
> Stateless/Stateful/State boilerplate before the composition layer freezes).
> Orient me on the current state and that review's options before changing code.
