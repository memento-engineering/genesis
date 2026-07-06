# Single-child links, the `nested` way — `SingleChildSeed` as a marker + `Nest` as a link

**Author:** AI (drafted with Nico, interactive session — human-ratified, not a register entry)
**Date:** 2026-07-05
**Governs:** `packages/tree/lib/src/single_child.dart` (rewrite), reads against ADR-0001
Decisions 3–5 (Branch purity), register A16/A21.
**Reference:** `package:nested` (rrousselGit) — `SingleChildWidget` / `Nested` /
`SingleChildWidgetElementMixin`.

---

## 1. What prompted this

Two coupled wishes:

1. **`Nest` should itself be a `SingleChildSeed`** so a `Nest` can be a link inside another
   `Nest` (chains compose / flatten).
2. The single-child stateless/stateful seeds should **build on the `StatelessSeed` /
   `StatefulSeed` / `State` primitives**, not re-clone them.

The old `single_child.dart` did neither. `SingleChildSeed` was a concrete base carrying a
`child` field, and the slot-in mechanism was a hard **downcast** inside the chain carrier:

```dart
// old _Link.createBranch()
node is SingleChildStatefulSeed ? _StatefulLinkBranch(this) : _StatelessLinkBranch(this);
// old _StatelessLinkBranch.build()
(link.node as SingleChildStatelessSeed).buildWithChild(context, link.next);
```

Anything that isn't one of those two concrete component subclasses fails the cast — so
`Nest` (or `InheritedSeed`) could never slot in, no matter what interface it declared. And
the stateful path was a **parallel clone**: `SingleChildState` re-implemented `State`'s whole
lifecycle, and `_StatefulSingleChildBranch` re-derived `StatefulBranch`'s
initState/didChangeDependencies flow.

## 2. The `nested` shape, ported

`package:nested` solves exactly this. The slot-in is not a downcast — it is a uniform
**element-side capability** (`SingleChildWidgetElementMixin on Element`): every single-child
element finds its enclosing hook at mount and, at build, injects that hook's downstream. The
marker interface `SingleChildWidget` is then *sufficient*; the capability lives in the mixin.
`Nested implements SingleChildWidget`, and `SingleChildState extends State`.

Ported to genesis:

| `nested` | genesis (this change) |
|---|---|
| `SingleChildWidget implements Widget` (marker) | `abstract interface class SingleChildSeed implements Seed` |
| `SingleChildWidgetElementMixin on Element` | `mixin SingleChildBranchMixin on Branch` |
| `SingleChildStatelessWidget extends StatelessWidget` | `SingleChildStatelessSeed extends StatelessSeed` |
| `SingleChildStatefulWidget extends StatefulWidget` | `SingleChildStatefulSeed extends StatefulSeed` |
| `SingleChildState extends State` | `SingleChildState extends State` |
| `StatelessElement with …Mixin` | `SingleChildStatelessBranch extends StatelessBranch with SingleChildBranchMixin` |
| `StatefulElement with …Mixin` | `SingleChildStatefulBranch extends StatefulBranch with SingleChildBranchMixin` |
| `_NestedHook` / `_NestedHookElement` (carries `injectedChild`) | `_NestHook` / `_NestHookBranch` |
| `Nested extends StatelessWidget implements SingleChildWidget` | `Nest extends Seed implements SingleChildSeed` |

**Why `SingleChildState extends State` and not `mixin SingleChildState on State`:** so a
user's shared `mixin FooBehavior on State` composes onto *both* a plain `State` and a
single-child one. Making `SingleChildState` itself the mixin would steal that slot. (Test:
`SingleChildState builds on State › a mixin on State composes onto both…`.)

**Result:** the parallel `State` clone and the bespoke stateful link branch are deleted;
single-child stateful now inherits `StatefulBranch`'s full lifecycle
(initState/didChangeDependencies/dispose, the initState/dispose `dependOn` asserts) for free.

## 3. The one subtle part — injected-child propagation

The hook topology means the node's own branch reads its downstream from a *separate* hook
parent. When a chain rebuilds, the node instance is reused (const), so
`updateChild` takes the identical-config fast path and does **not** rebuild the node — its
new downstream would never reach the leaf. `nested` handles this with the `injectedChild`
setter calling `visitChildren(markNeedsBuild)`. genesis does the same in
`_NestHookBranch.update`, but **synchronously** (`_child.rebuild(force: true)`), because
genesis's update cascade is synchronous and callers (`root.update(...)`) read results without
an intervening `flush()`. A node that itself changed was already rebuilt by `performRebuild`,
so the force is guarded to fire only when *just* the downstream changed:

```dart
if (identical(old.node, now.node) && !identical(old.injected, now.injected)) {
  _child?.rebuild(force: true);
}
```

This reproduces the existing "whole chain rebuilds on any change" behaviour and the
identical-`Nest` skip (which still happens one level up, at the parent's `updateChild`).

## 4. Branch purity (ADR-0001 D3 / register A31)

`SingleChildBranchMixin` is a composition-layer mixin *on* `Branch`; it adds no
render/gesture/timer/listener machinery to `Branch` core — it only reroutes which downstream
a build embeds. `Branch` itself is untouched.

## 5. Compatibility / blast radius

- **`SingleChildSeed`: concrete base → interface.** No production code subclasses it (only
  `tree`'s own tests, which extend the concrete `SingleChild{Stateless,Stateful}Seed` — those
  stay `abstract class` you extend). `perception`/`typesetting` use `InheritedSeed` and the
  `dependOn` API, never the single-child hierarchy.
- **`Nest.child`: required → optional (nullable).** Source-compatible for every existing
  caller; enables the leaf-less nested-link form. An interface-semantics change ⇒ `genesis_tree`
  **minor** bump under pre-1.0 discipline.
- Whole workspace green (tree 203, perception 109, typesetting/dialogue/consent/taxonomy/tmux
  all pass); `dart analyze` clean.

## 6. Deliberately out of scope (follow-ups)

- **`InheritedSeed` as a link.** The same seam now admits it (an `InheritedBranch with
  SingleChildBranchMixin` variant — `nested`'s `SingleChildInheritedElementMixin`), which would
  let a provider sit directly in a `Nest` without a wrapper. Left out to keep this reviewable;
  it also carries a `child` required→nullable change on `InheritedSeed` and a `perception`
  (`InheritedPerception`) ripple.
- **Extra branch per link.** The hook topology adds one hook branch per link (as `nested`
  does). Not labelled, no behavioural cost observed; noted for the record.
