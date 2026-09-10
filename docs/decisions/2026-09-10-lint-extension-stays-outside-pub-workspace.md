---
status: accepted
date: 2026-09-10
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: lint-extension-stays-outside-pub-workspace
  surfaces:
    - "analysis_options.yaml"
    - "pubspec.yaml"
    - "packages/lint/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-ztl
  legacy-id: null
---

# lint extension stays outside the pub workspace

## Context and Problem Statement

ADR-0001 Decision 7 establishes “Dart pub workspace + melos” as the package
convention under `packages/**`. `genesis_lint` is a tooling exception to that
workspace clause, not an accidental omission. Its `analysis_server_plugin`
0.3.22 dependency pins `analyzer` exactly to 14.3.0, while the genesis pub
workspace resolves `analyzer` 13.3.0. A pub workspace has one shared
resolution, so membership would make the analysis extension choose the
engine's analyzer major and repeat that coupling whenever the SDK lockstep pin
moves.

The exception does not change ADR-0001's workspace convention for runtime
packages. It narrowly overrides that convention for `packages/lint`, whose
analyzer-protocol dependencies must remain separate from the pure-Dart tree
engine and every other workspace member.

## Decision Outcome

`packages/lint` remains outside the root `workspace:` list and omits
`resolution: workspace`. It resolves `analysis_server_plugin` 0.3.22 and
`analyzer` 14.3.0 in its own package lock, while the root workspace continues
to resolve `analyzer` 13.3.0. The root enables the extension through the
top-level `plugins:` section of `analysis_options.yaml`; `genesis_tree` does
not depend on the lint package or its analyzer dependencies.

This decision is also a scoped exception to A32's statement that
`resolution: workspace` stays for member packages. Its hosted-dependency rule
still applies: both analyzer-protocol dependencies use hosted exact
constraints.

### Consequences

* Good, because analysis tooling cannot grow `genesis_tree`'s dependency
  surface or select the workspace analyzer version.
* Good, because SDK-driven analyzer pin changes remain local to the extension.
* Bad, because repository tooling must enter `packages/lint` for its own
  resolution and tests instead of relying on melos workspace membership.

## Alternatives Considered

Add `packages/lint` to the pub workspace for melos convenience. Rejected: the
benefit is avoiding one directory change in scripts, while the cost is letting
an analyzer extension choose a major analyzer version for the tree engine and
all other workspace packages.
