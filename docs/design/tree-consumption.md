# Consuming `genesis_tree`: the D–H doctrine

These five rules are ratified house style for any code that consumes
`genesis_tree`. They keep tree construction synchronous and descriptive, make
changing inputs observable, and keep I/O outside the declarative tree. Each rule
states whether the library enforces it or whether it remains a convention for
consumer code.

They elaborate [ADR-0006](../adr/ADR-0006-pull-free-build.md) and the branch
purity invariant in [ADR-0001](../adr/ADR-0001-foundations.md).

## Rule 1 — Track every changing dependency

Always watch every changing dependency that affects `build()`. For an inherited
value, call `dependOnInheritedSeedOfExactType()` in `build()`, or cache its
result from `didChangeDependencies()`. `dependencyChanged()` causes
`didChangeDependencies()` to run again before the next build, so that method
must repeat the read and replace the cached value. Use
`getInheritedSeedOfExactType()` only for a deliberately one-shot snapshot whose
later changes must not rebuild the reader. Never initialize a reactive cache
once and leave it detached from its source.

**Enforcement:** Code-enforced — debug-mode asserts at
`packages/tree/lib/src/stateful.dart:100-122` directly guard this
cache-and-track rule. They reject dependency-watching reads during `initState`
and `dispose`, direct one-shot reads to `getInheritedSeedOfExactType()`, and
direct cache-and-track reads to `didChangeDependencies()`. The same range shows
`dependencyChanged()` marking the lifecycle callback and rebuild for another
pass.

## Rule 2 — Never synchronously read reactive state without subscribing

A synchronous read of reactive state must occur behind an active subscription
that causes the reader to rebuild or refresh. Do not publish a public state
mirror that returns the current value while leaving callers unaware of later
changes. Pass an immutable current value, expose a subscription, or make the
read from the object that already owns the subscription.

**Enforcement:** Convention — `genesis_tree` cannot determine whether an
arbitrary consumer accessor has a matching subscription. Reviews and consumer
tests must prove the invalidation path for every reactive read.

## Rule 3 — Keep service access out of seeds and branches

`Seed` objects carry immutable configuration values. `Branch` objects and
composition code may touch value types and reactive domain objects; they must
not locate or call service-layer APIs. A long-lived object can enter through
dependency injection or composition only, and tree code can carry its reference
onward without doing that object's work.

**Enforcement:** Convention — the generic library cannot identify consumer
service types or dependency-injection choices. Reviews keep service lookup and
service calls outside seeds and branches.

## Rule 4 — Pure description delegates may be created during build

A delegate class is acceptable in `build()` only when it is pure description.
Its creation and getters may describe data or behavior, but may not perform I/O,
begin work, listen to sources, or mutate state outside itself. It is a
value-shaped description, not a service.

**Enforcement:** Convention — no generic runtime check can distinguish a pure
description object from a service-shaped delegate. Reviews and focused consumer
tests enforce the no-effects requirement.

## Rule 5 — Carry I/O services unchanged to the effect boundary

Pass an injected I/O service unchanged through configuration and composition to
an effect boundary. Only that boundary may call it, start or stop it, or turn
its results into a current value watched by the tree. Unchanged means the same
service object remains responsible for its behavior; intermediate tree code
neither wraps nor samples it. `build()` never gathers from the service, awaits
it, or exposes an untracked snapshot of it.

**Enforcement:** Convention — `genesis_tree` has no knowledge of consumer I/O
types or effect boundaries. Reviews and boundary tests must prove that tree code
only transports the service.
