---
status: accepted
date: 2026-10-04
decision-makers:
  - "Nico Spencer"
consulted:
  - "Claude (grid-v2 session)"
informed: []
register:
  spec: 1
  slug: watch-nullability-follows-the-type-argument
  surfaces:
    - "packages/tree/lib/src/provider.dart"
    - "packages/tree/lib/src/lifecycle_provider.dart"
    - "packages/tree/lib/src/tree_lifecycle_participant.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# `watch<T>()` nullability follows the type argument

## Context and Problem Statement

The provider layer's lookup verbs are declared `T? watch<T extends Object>()` and
`T? read<T extends Object>()` (`provider.dart`, `lifecycle_provider.dart`,
`tree_lifecycle_participant.dart`): the result is always nullable, absence of a provider is
a designed posture, and the `extends Object` bound forbids a nullable type argument. Two
consequences showed up in the consumers. A caller that *requires* the value cannot say so and
gets a silent `null` to defend against — of 812 `watch`/`read` call sites across the_grid,
power_station and space_station, 189 null-handle inline and the rest dereference by
assumption. And a caller that *accepts* absence cannot express that in the type either,
because `watch<T?>()` does not compile.

Nico, 2026-10-04: "`watch<T>()` should return `T` or throw while `watch<T?>()` should return
`T?`."

## Decision Outcome

**D1.** `watch<T>()` and `read<T>()` return `T`. When no provider of `T` is in scope they
throw a loud `StateError` that names the type and the requesting element; a missing
dependency is a composition defect, not a value.

**D2.** `watch<T?>()` and `read<T?>()` return `null` for absence. The `extends Object` bound is
dropped from the lookup pair and from `InheritedComponent`/`InheritedElement`; the verb is one
lookup, one `null is! T` check, one cast. Absence as a designed posture is now expressed by the
caller choosing a nullable type argument, which is where the knowledge of whether absence is
acceptable actually lives.

**Mechanism (the `package:provider` approach).** A provider registers its inherited element
under the *nullable spelling* of its type (`Provider<X>` mounts `InheritedComponent<X?>`), and
every lookup verb asks for the nullable spelling (`dependOnInheritedValueOfExactType<T?>()`).
`X` and `X?` therefore normalize to one key, the spine's exact-type match is untouched, and the
pending registry has one bucket per type by construction. Consequence: `watch<X>()` finds
providers, not a plain `InheritedComponent<X>` — the same split Flutter has between
`context.watch` and `dependOnInheritedWidgetOfExactType`.

**D3.** The derived-provider family (`ProxyProvider` through `ProxyProvider6`) follows the
declared input types: an input declared non-nullable makes the proxy unavailable until it is
present; an input declared nullable is passed as `null`. The `AvailabilityRegistry`'s
pending-by-type watch is unchanged.

**D4.** This ships as a breaking change on the next dev minor of `genesis_tree`. Consumers that
keep the old posture migrate by writing `T?`; nothing is aliased. `the_grid` does not adopt it
— it is being replaced and its call sites are not worth migrating; `grid` adopts from first
use.

### Consequences

- The "nullable always" posture documented at the lookup verbs is amended to "nullable when
  asked".
- A `genesis_lint` rule can flag `watch<T>()` followed by a null check (the check is dead) and
  `watch<T?>()!` (the caller wanted `watch<T>()`).
- Implementation is pending at the time of this entry; the surfaces above are the files it
  changes.
