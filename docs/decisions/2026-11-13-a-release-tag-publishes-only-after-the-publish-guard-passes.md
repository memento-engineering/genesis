---
status: accepted
date: 2026-11-13
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: a-release-tag-publishes-only-after-the-publish-guard-passes
  surfaces:
    - ".github/workflows/publish.yml"
    - ".github/workflows/ci.yml"
    - "tool/publish_guard.sh"
    - "tool/publish_guard_test.sh"
    - "tool/publish_workflow_test.sh"
    - "tool/test_fixtures/publish_guard/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: genesis-nat
  legacy-id: null
---

# A release tag publishes only after the publish guard passes

## Context and Problem Statement

A release tag `<package>-v<version>` publishes a package to pub.dev. The
publish workflow parsed the tag into a package directory and uploaded it,
checking nothing at the tagged commit. A tag pushed on a commit whose pubspec
still held the previous version published the wrong thing or failed late at
pub.dev, and a dependent tagged before its dependency had published failed
its resolution after release. Dependency-order publishing (genesis#a32) was a
convention a tagger had to remember, and the org's rule that a release is a
bump PR then a guarded tag push had no guard on the publishing side.

## Decision Outcome

**D1.** A release tag publishes only after a guard on the publishing side
passes against the tagged commit. The guard runs whatever pushed the tag, so
it does not depend on a station-side check having run first.

**D2.** A sibling the released package depends on is ready only when pub.dev
lists the exact version that sibling declares at the tagged commit. A version
merely satisfying the dependent's constraint is not enough. This makes
dependency-order publishing (genesis#a32) a refusal rather than a convention.

**D3.** Only runtime dependencies gate a release. Development dependencies and
overrides do not, because they never reach a consumer's resolution.

**D4.** The guard reads nothing from the network but pub.dev's package
listing. Its tests serve that read from fixtures and run in CI on every
change.

### Consequences

* Good, because a tag on an unbumped commit, or one with no changelog entry
  for its version, stops before any upload instead of failing late.
* Good, because a dependent cannot reach pub.dev ahead of the sibling release
  it was built against.
* Bad, because a dependent's tag pushed too soon fails and must be re-run
  once its sibling's release lands, rather than waiting on its own.
* Bad, because the guard reads pubspecs and changelogs as plain text, so a
  pubspec shape it does not expect is read by its rules, not by pub's.

### Confirmation

This entry is falsified by any of: a tag published while its pubspec reads
another version; a tag published with no CHANGELOG heading for its version; a
dependent published before pub.dev lists its sibling's declared version; a
guard test that reaches the network.
