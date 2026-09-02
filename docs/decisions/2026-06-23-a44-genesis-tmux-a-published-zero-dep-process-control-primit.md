---
status: accepted
date: 2026-06-23
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a44-genesis-tmux-a-published-zero-dep-process-control-primit
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A44"
---
## A44 (2026-06-23) — `genesis_tmux`: a published, zero-dep process-control primitive in the substrate  ·  AI (records the_grid A34 from genesis's side)

**Decision:** `genesis_tmux` (`packages/tmux`) — a zero-dependency, injection-safe tmux client for supervising long-lived agent panes (Tier-1 verbs + a poll/control-mode observation stream behind a single fakeable `TmuxExecutor` seam) — is a **first-class, published genesis member**: listed in `release-scope.md`'s member set, in the README/CLAUDE package tables, and shipped under the `memento.engineering` verified publisher alongside the other members. It carries **no `genesis_tree` dependency** (only `meta`) and is consumed by `leonard_tmux` (hosted `^0.1.0`) and the_grid's planned `grid_runtime` `TmuxProvider` (sibling path dep during dev → hosted at stabilization, the ADR-0001 D8 pattern).
**Why:** the package was built and published at 0.1.0 *ahead of* any genesis-side decision record — the relocation call lived only in **the_grid's** register (the_grid ADR-0000 A34, Nico 2026-06-15). This amendment records it in genesis's own register and answers the standing "why does a process-control client live in the Seed/Branch substrate?" question explicitly: (a) genesis's ratified **A4** already names tmux the terminal-real-estate primitive a genesis render backend "draws into"; (b) it is craft-named and domain-free, satisfying **A16**'s naming rule (a human craft, never an agent-noun — `tmux`, not `supervisor`); (c) it is the **shared** process-control primitive both consumers (lenny, the_grid) need, so the neutral substrate is its natural home rather than either consumer owning it. The counter-argument — a zero-engine-dep utility could equally live in a standalone shared lib — is acknowledged and set aside in favour of the existing A4 lineage and a single substrate home; revisit only if a non-genesis consumer needs it without the rest of genesis.
**Affects:** `release-scope.md` (member set six → seven; publish checklist gains tmux); `README.md` + `CLAUDE.md` package tables (+ `apps/console`); `packages/tmux/pubspec.yaml` (description trimmed to pub's 180-char limit); `packages/tmux/HANDOFF.md` (status corrected — built/shipped 0.1.0, was "build not started"). **Operator action: DONE** — `genesis_tmux` is under the `memento.engineering` verified publisher (pub.dev `publisherId` verified 2026-07-21); this line originally requested that transfer while the amendment sat unlanded. **Status:** pending — Nico to promote (into ADR-0001's package-set foundations, or as a one-line ADR note) or reject.

