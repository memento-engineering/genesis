---
status: accepted
date: 2026-10-04
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: tree-shape-lint-rules-scope-and-marker-annotations
  surfaces:
    - "packages/lint/**"
    - "packages/foundation/lib/src/annotations.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Tree-shape lint rules: their scope, and the marker annotations they read

## Context and Problem Statement

`genesis_lint` 0.3.0-dev.1 adds six warnings that keep consumer tree code
declarative: `no_effects_in_build`, `no_cached_dependency`,
`watch_not_read_in_build`, `derive_dont_construct`, `state_flag_threshold` and
`effects_only_in_leaves`. Three of them read intent the type system cannot
express, so they need annotations; each rule also needed a boundary between
what it rejects and what it leaves alone. Where a rule cannot tell correct
code from incorrect, it stays silent rather than fire; the known blind spots
are listed under Consequences. These calls were made without a human in the loop and are not
covered by an existing entry.

## Decision Outcome

**Annotations live in `genesis_foundation`** as const markers: `deriveOnly`
(class `DeriveOnly`), `effect` (class `EffectMarker`) and `effectLeaf` (class
`EffectLeafMarker`). The foundation is dependency-free and sits below
`genesis_tree`, which re-exports it, so a consumer reaches the markers through
either import. The marker classes are not named `Effect` / `EffectLeaf`
because a consumer orchestrator is expected to own types by those names, and a
re-exported collision would make every shared import ambiguous. The rules
match a marker by its declaring library, never by name alone.

**Rule boundaries:**

- A build is a `build` or `buildWithChild` method on a `genesis_tree`
  `Component` or `State` subclass. `buildWithChild` is the build of the
  single-child composition classes and carries the same contract.
- The six rules report at warning severity, so `dart analyze` fails when one
  fires and a consumer's analyze gate enforces them without configuration.
- The build-scoped rules check the code a build runs before it returns: its
  body, a closure invoked on the spot or handed to a `dart:core` or
  `dart:collection` method (or a `generate` / `fromIterable` constructor),
  and a local function the build calls or hands to such a method. A closure
  handed anywhere else (a callback, a hook effect) runs later and is not
  checked.
- `no_effects_in_build` treats locals and parameters as transient. A property
  or index write is local when its receiver is a local variable or a value
  made on the spot (a literal or constructor call, directly or as a cascade
  target); every other write target — a field, a top-level or static
  variable, a property or index of any other object — is durable.
  `Stream.listen` counts as an effect.
- `no_cached_dependency` applies only to durable targets: a `??=` into a local
  is not a cache. A `??=` whose value is itself a `BuildContext` (an Element
  lazily wrapping its own handle) is not a dependency read and is left to
  `no_stored_tree_context`.
- `effects_only_in_leaves` accepts an `@effect` call inside an `@effectLeaf`
  class only from its `startOrAdopt`, `update` and `dispose` methods and the
  members of the same class they reach by call or tear-off; a constructor, a
  field initializer, a build and any unreached member are rejected. It
  inherits `@effectLeaf` through supertypes, treats an override of an
  `@effect` member as an effect, and lets an `@effect` declaration invoke
  other effects so effects compose.
- `state_flag_threshold` counts `bool` and `bool?` instance fields the class
  itself declares; inherited fields are not counted.
- Like the two existing rules, none of the six reports in a `test/` directory.

### Consequences

* Good, because each rule's silent cases are pinned by tests and the genesis
  workspace itself analyzes clean with all eight rules enabled.
* Good, because the markers add no dependency and no runtime behaviour.
* Bad, because a `State` spreading flags across an inherited base class, an
  effect reached through a tear-off, and an implicit `super()` call into a
  `@deriveOnly` class are not detected.
* Bad, because the build rules do not see through aliases or dynamic
  dispatch: a field written through a local alias, a closure stored in a
  variable and then called, a callback run by a non-core helper, a `Future`
  read from a getter, and an `@effect` override reached through an
  unannotated supertype member are not reported. Each would need whole-program
  or flow analysis, and guessing would fire on correct code.

## Considered Options

Name the marker classes `Effect` and `EffectLeaf`. Rejected: the re-export
through `genesis_tree` would collide with a consumer's own effect types.

Reject a `??=` of any context read, including into locals. Rejected: a local
cannot outlive the call, so the warning would fire on correct code.
