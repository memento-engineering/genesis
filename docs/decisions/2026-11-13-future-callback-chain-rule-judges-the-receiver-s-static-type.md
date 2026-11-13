---
status: accepted
date: 2026-11-13
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: future-callback-chain-rule-judges-the-receiver-s-static-type
  surfaces:
    - "packages/lint/lib/src/rules/no_future_callback_chains.dart"
    - "packages/lint/README.md"
    - "packages/tmux/lib/src/client.dart"
    - "packages/tmux/lib/src/control_source.dart"
    - "packages/tmux/lib/src/process_executor.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-5si
  legacy-id: null
---

# The Future callback chain rule judges the receiver's static type

## Context and Problem Statement

memento code writes asynchronous Dart with `async` and `await` and never
chains a callback onto a future, and a genesis lint rule is to enforce it,
with no code exempt. Building that rule leaves open which calls it treats as
a chain, how it meets `FutureOr`, whether it follows the existing rules out
of test directories, and how genesis's own chains are converted. The work
also found eight chains in genesis where the work item counted seven.

## Decision Outcome

**D1.** The callback-chain rule judges a call by the static type of its
explicit receiver: a Future, a subtype of one, a nullable Future, or a type
variable bounded by one. Where the receiver cannot be typed that way — a
dynamic receiver, an implicit receiver, a member read but not called — the
rule stays silent rather than guess.

**D2.** A FutureOr value carries none of the chaining members until it is
narrowed to a Future, so the rule meets FutureOr through that narrowing.
This amends the work item's FutureOr wording to the reading the language
allows.

**D3.** The rule reports in test code as it does in library code, at warning
severity. The test-directory exemption of the tree-shape rules stays scoped
to those six rules and does not extend to this one.

**D4.** Converting genesis's own chains keeps each chain's error handling
exactly: a failure a chain swallowed stays swallowed, and a failure it
surfaced stays surfaced to the same caller. The conversion covers every
chain the rule finds — eight, where the work item counted seven.

### Consequences

* Good, because the rule fires on every typed chain, including chains in
  tests, so `dart analyze` keeps the whole repository on one async style.
* Good, because silence on untyped receivers keeps the rule free of false
  positives on code it cannot judge.
* Bad, because a chain on a dynamic receiver, or on the implicit receiver
  inside a class implementing Future, is not caught.

### Confirmation

This entry is falsified by any of: a Future callback chain in genesis code,
analysed under the root analysis options, that draws no warning; a warning
on a receiver that is not a Future; a change in a tmux behaviour the
existing tests pin.
