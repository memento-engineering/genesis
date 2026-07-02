# Publishing — house rules

The seven published members ship to pub.dev under the **`memento.engineering`
verified publisher**. People consume these packages now: every release follows
this document. (`docs/release-scope.md` records the original 0.1.0 launch and
the 1.0 boundary; this doc governs the releases in between.)

## When to publish

- **A consumer needs the version resolvable** — a sibling repo wants to drop a
  path override, or a workspace member's constraint points at an unpublished
  version. An unpublished pair (e.g. a `tree` API only reachable via path
  links) is a bug in the release state, not a steady state.
- **Docs-only refresh** — pub.dev renders the README/CHANGELOG/dartdoc frozen
  into the archive at publish time, never GitHub. Docs-only releases are cheap
  and encouraged (precedent: `genesis_perception` 0.1.1, `genesis_tree`
  0.1.5); say "Docs only, no API changes" in the CHANGELOG.

## Version discipline (pre-1.0, with real consumers)

- **Additive API, fixes, docs → patch** (`0.1.x`).
- **Breaking → minor** (`0.1.x` → `0.2.0`), and the CHANGELOG entry leads with
  **Breaking:** and a migration line. In the `0.x` range pub reads `^0.1.0` as
  `>=0.1.0 <0.2.0`, so a breaking *patch* silently reaches every existing
  resolver — the `0.1.3`/`0.1.4` breaking-in-patch releases predate outside
  adoption and are grandfathered, not precedent.
- **Adding a member to an exported abstract interface is breaking** for
  external implementers (the `TreeContext` lesson), even when every in-repo
  handle just delegates.
- **Cross-package coherence:** when a sibling consumes API introduced in
  version X, tighten the sibling's constraint to `^X` in the same change
  (precedent: `perception` → `genesis_tree: ^0.1.4`) and release in
  dependency order so a resolved pair is always coherent.

## Pre-publish gates — all mandatory, in order

1. **Workspace green:** `melos run analyze` · `melos run test` ·
   `melos run format`.
2. **The scrub gate:** nothing the archive ships or pub.dev renders carries
   internal references — no ADR/register numbers, no spike/evidence names, no
   sibling-repo domain nouns. Covers `README.md`, `CHANGELOG.md`, all `lib/`
   doc comments, and `example/`. Check from the package dir:

   ```bash
   grep -rniE "ADR-?[0-9]|register|\bA[0-9]{1,2}\b|spike" \
     README.md CHANGELOG.md lib example 2>/dev/null | grep -viE "A2UI"
   ```

   (Expect no output. `A2UI` is the one sanctioned false positive.)
3. **No internal working docs inside the package dir.** Handoffs, scratch,
   and design notes ship in the archive if they live under `packages/<p>/` —
   their home is `docs/evidence/` (precedent: the tmux build handoff).
4. **CHANGELOG entry + version bump, committed.** The dry-run flags
   uncommitted package files; treat *any* warning as a stop.
5. **`dart pub publish --dry-run` → 0 warnings.**

## Publishing

- **Dependency order:** `tree` → { `perception`, `taxonomy`, `typesetting` }
  → `dialogue` → `consent`; `tmux` is independent (only `meta`).
- After each upload, poll `https://pub.dev/api/packages/<name>` until the new
  version is `latest` **before** publishing a dependent (it lands within a
  minute or two).
- `dart pub publish` from the package dir. `--force` only when the dry-run
  just passed clean.

## Post-publish

1. **Tag the release commit** `<pub-name>-v<version>` (e.g.
   `genesis_tree-v0.1.5`) and push tags — tags exist from 2026-07-02 onward
   and are what lets `melos version` take over bumping later.
2. Push `main`.
3. Verify the version resolves via the API, and spot-check the rendered
   README on the package page (it can lag a few minutes).

## Publisher & ownership

- All members live under the `memento.engineering` verified publisher; new
  versions inherit it with no re-transfer.
- Outstanding: `genesis_tmux` was published outside the publisher and still
  needs the one-time **Admin → Transfer to Publisher** (see
  `docs/release-scope.md` item 7).
