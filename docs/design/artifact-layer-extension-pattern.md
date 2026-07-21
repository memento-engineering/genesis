# The artifact layer — the four pieces every genesis consumer defines

**Author:** AI (drafted from the tree, unattended) — an explanatory doc, not a decision
**Date:** 2026-07-20
**Governs:** no `lib/` code. This is the long-form companion to `packages/tree/README.md`
§"The artifact layer — deliberately not shipped", which carries the shipped summary; the
worked examples live here because a published archive may not carry internal references
(`docs/publishing.md`, the scrub gate).
**Reads against:** `docs/adr/ADR-0001-foundations.md` (Decisions 2, 3, 4, 5, 6) and
`docs/adr/ADR-0004-render-backends.md` (Decision 2).
**Worked examples:** `packages/typesetting`, `packages/perception`, and — outside this repo —
the_grid's Allocation Tree.

---

## 1. Why the spine stops at `Seed` → `Branch`

Flutter's stack is three layers: `Widget` (immutable config) → `Element` (persistent
lifecycle + keyed reconcile) → `RenderObject` (the persistent artifacts that do the real
work). `genesis_tree` ports the first two and stops there on purpose. It reconciles desired
state into live identity; **what that identity spawns and owns — the artifact layer — is the
consumer's.**

The stop is a ratified constraint, not an omission. ADR-0001 Decision 3
(`docs/adr/ADR-0001-foundations.md`):

> **`Branch` core is artifact-agnostic** — identity, lifecycle, keyed reconcile, dirtiness,
> and **one abstract rebuild hook** (the `performRebuild` analog). It carries **no build
> contract**.

and its Branch-purity amendment, folded into the same Decision:

> `Branch` stays exactly **identity + keyed reconciliation + dirtiness**, plus the one
> abstract `performRebuild` hook with no build contract. It **refuses** the accretion that
> bloated Flutter's `Element`.

Flutter *bundles* its artifact layer and fixes its shape: `RenderObject` nodes, a
`PipelineOwner`, the layout/paint/hit-test protocol, and `Theme`/`MediaQuery` ambient scopes
are all framework. genesis **unbundles** those four pieces. This document names them and
walks the consumers that define them differently, so the next consumer does not rediscover
the pattern from scratch.

The four pieces at a glance:

| Piece | Flutter bundles | `genesis_typesetting` defines | `genesis_perception` defines |
|---|---|---|---|
| **Artifacts** | `RenderObject` | `RenderBranch` — the branch *is* the artifact (owns `rect`, paints cells) | the mounted element itself — `NodeElement` / `FieldElement` |
| **Owner** | `PipelineOwner` | `StageBinding` — the dirty-paint set and the frame pass | none; the harvest is pulled, so `PerceptionOwner` only renames `TreeOwner` |
| **Protocol** | layout / paint / hit-test | `flowHeight` → `layout(Rect)` → `paint(CellGrid)` | `serializePerceptionFragment(Branch)` — a read over the live tree |
| **Affordance scopes** | `Theme` / `MediaQuery` | `InheritedSeed<RenderParentLink>` — render-parent threading | `InheritedPerception<T>` — ambient measurement values |

Note the asymmetry. Perception defines two of the four pieces trivially: its artifacts *are*
its branches, and it needs no second scheduler. That is the point of unbundling — a consumer
pays only for the pieces its domain actually uses.

## 2. The four pieces

### 2.1 Artifacts — what desired state spawns

An artifact is the persistent, live thing a mounted branch owns: a painted region, a
harvestable datum, a spawned process, a held lease. The question that finds it is **"what
does this branch own that outlives a single rebuild?"**

Two shapes are both correct:

- **The branch *is* the artifact.** `RenderBranch` collapses Flutter's `RenderObjectElement`
  and `RenderObject` into one type — ADR-0004 Decision 2
  (`docs/adr/ADR-0004-render-backends.md`): "A cell grid is a single immediate surface, so
  there is no separate retained render node to keep: the branch *is* the render object."
  Cheapest; use it when the artifact's lifetime is exactly the branch's.
- **The branch *holds* the artifact.** The branch creates a separate object at mount and
  disposes it at unmount. Use it when the artifact must outlive, or be handed across, branch
  identity — the_grid's `Allocation` is this shape (§5).

Either way: mount creates, unmount disposes. `Branch.mount` and `Branch.unmount`
(`packages/tree/lib/src/branch.dart`) are the only lifecycle hooks the spine offers, and they
are enough.

### 2.2 Owner — the pass scheduler beside `TreeOwner`

`TreeOwner` (`packages/tree/lib/src/tree_owner.dart`) schedules exactly one pass: the
**build** pass. It holds the dirty set, fires `onNeedsFlush` on the empty→non-empty edge, and
`flush()` drains depth-ordered and **returns the branches it rebuilt** — ADR-0001 Decision 5:
"A flush must hand the backend *what rebuilt*." Your artifact pass is a second scheduler that
consumes that return value.

The shape typesetting uses (`StageBinding`, `packages/typesetting/lib/src/stage.dart`):

```dart
// The binding claims the tree's flush edge at mount, then owns the frame:
//   owner.onNeedsFlush -> scheduleMicrotask(_framePass)
void _framePass() {
  final rebuilt = _owner.flush();   // the build pass runs FIRST
  _renderFrame(rebuilt);            // then the artifact pass, over what rebuilt
}
```

Three rules earned the hard way:

1. **The build pass runs first.** Flush, then run your pass over the drained list — never
   interleave the two.
2. **`onNeedsFlush` is single-listener.** The binding asserts-and-claims it at mount
   (ADR-0004 Decision 2: "a `Stage` must be the only consumer of that hook"). Two artifact
   owners on one `TreeOwner` is not a supported shape today; it would need a multi-listener
   edge on `TreeOwner`, a request the tree has deliberately not been asked for.
3. **You may not need an owner at all.** If your artifacts are *pulled* rather than pushed —
   perception's harvest — skip it. `PerceptionOwner`
   (`packages/perception/lib/src/perception_owner.dart`) adds no scheduling whatsoever: it
   renames `flush()` to `flushHarvest()` and `onNeedsFlush` to `onNeedsHarvest`, and inherits
   the rest.

### 2.3 Protocol — the pass your artifacts run

The protocol is what the pass *does* to the artifacts. `Branch` gives you exactly one hook to
respond to a config change — `performRebuild()` — and ADR-0001 Decision 4 fixes when it
fires: a keyed in-place update "**invokes the Branch's rebuild hook** — *unless the new seed
is `identical()` to the mounted one*". Everything past that hook is yours.

Typesetting's protocol is three-phase (ADR-0004 Decision 2): a child reports the rows it
occupies via `flowHeight`, the parent assigns geometry top-down via `layout(Rect)`, then
`paint(CellGrid)` writes cells. Its artifact response to a rebuild is *registration*, not
work:

```dart
// packages/typesetting/lib/src/render_branch.dart
@override
@mustCallSuper
void performRebuild() {
  markNeedsLayout();
  markNeedsPaint();
}
```

Perception's protocol is a **read**: `serializePerceptionFragment(Branch)`
(`packages/perception/lib/src/serialize.dart`) walks the live tree with the spine's shallow
`visitChildren` and folds `NodeElement`/`FieldElement` into a JSON map. No dirty set, no pass
scheduling — the measurement is harvested when someone asks for it.

Two protocol invariants worth copying:

- **Traverse with `visitChildren`, not a private child list.** It is shallow, tree-ordered,
  and the caller recurses (ADR-0001 Decision 5). Typesetting derives its render adjacency
  that way, which is what makes component branches between two render branches transparent:
  `RenderBranch.renderChildren` descends until it hits the nearest `RenderBranch`.
- **Keep the pass out of `Branch`.** Both examples put every scheduling primitive
  (`markNeedsPaint`, `markNeedsLayout`, the frame microtask) on the *subclass*, never on the
  spine — the purity invariant, made literal.

### 2.4 Affordance scopes — the ambient values your layer reads

An affordance scope is a value a branch reads from its ancestors instead of being handed it
explicitly: Flutter's `Theme`, `MediaQuery`. In genesis it is `InheritedSeed<T>` +
`dependOnInheritedSeedOfExactType<T>()` — the one Element-bloat category the spine
deliberately carries, ratified in ADR-0001 Decision 3 as "a pure structural tree-query (not a
growing callback registry), load-bearing for providers and render-parent threading", with the
dependent set allocated lazily so a branch with no dependencies pays nothing.

Typesetting's use is structural rather than thematic — it threads the render parent, which
ADR-0004 Decision 2 calls the mechanism's "**second structural consumer**":

```dart
// packages/typesetting/lib/src/render_branch.dart — the container side
@protected
Seed renderScopeFor(Seed child) {
  final childKey = child.key;
  return InheritedSeed<RenderParentLink>(
    value: _link,                                    // identity-stable: never notifies
    child: child,
    key: childKey == null ? null : _RenderScopeKey(childKey),
  );
}

// …and the mounting-child side
@protected
void attachRenderParent() {
  final link = dependOnInheritedSeedOfExactType<RenderParentLink>();
  link?.branch.adoptRenderChild(this);
}
```

Two details there are load-bearing, not incidental:

- **The wrapper's key is namespaced** (`_RenderScopeKey`), never the child's own key.
  Reusing the bare child key would mint a second branch answering to that key, and any
  key-based lookup — an action router resolving a component id, say — would find two.
- **The provided value is identity-stable**, so re-providing it on every rebuild never
  notifies dependents.

**When a scope must carry domain *capabilities* rather than ambient values, layer them onto
the context handle — never make the branch its own context.** ADR-0001 Decision 2
(`docs/adr/ADR-0001-foundations.md`, "The tree spine: `Seed` → `Branch`; `TreeContext` is a
separate handle") is the constraint:

> **The fork — shed Flutter's Element≡BuildContext "original sin":** `Branch` does **not**
> implement `TreeContext`. The context is a *distinct capability handle* passed to `build()`,
> never the mounted node itself.

Decision 2's reason is agent-shaped: "agents routinely hold handles across async gaps: an
agent reads a projection, deliberates for seconds, then acts." The separate handle throws
after unmount; a branch-as-context would silently act on a dead node. So the sanctioned move
is *wrapping*: `PerceptionContext implements TreeContext` over a private handle that
delegates every base member and adds `markNeedsHarvest` / `perceptionId`
(`packages/perception/lib/src/perception_context.dart`) — what ADR-0001 Decision 6 calls "a
capability extension of `TreeContext` — the domain layers budget/harvest capabilities onto
the handle, which is exactly what Decision 2's separate-handle architecture is for."

## 3. Worked example — `genesis_typesetting`, a character grid

| Piece | What it is | Where |
|---|---|---|
| Artifacts | `RenderBranch` and its subclasses `StageBranch` / `BoxBranch` / `TextBranch` — each owns a `Rect` and paints cells | `packages/typesetting/lib/src/render_branch.dart` |
| Owner | `StageBinding` — the `PipelineOwner` analog: a depth-sorted dirty-paint set, one microtask frame pass, a `FrameRecord` per pass | `packages/typesetting/lib/src/stage.dart` |
| Protocol | `flowHeight` → `layout(Rect)` → `paint(CellGrid)`, drained parent-first by `paintSubtree` | `packages/typesetting/lib/src/render_branch.dart` |
| Affordance scope | `InheritedSeed<RenderParentLink>`, provided by `renderScopeFor` and resolved by `attachRenderParent` | `packages/typesetting/lib/src/render_branch.dart` |

The mount path, end to end:

1. `owner.mountRoot(Stage(...))` mounts a `StageBranch`, which creates the one `StageBinding`
   and claims `TreeOwner.onNeedsFlush`. Frame 0 paints synchronously at mount, so mounting
   the stage *is* the entry shape.
2. Every render container wraps each child seed in `renderScopeFor(child)` before reconciling
   it, so the child mounts inside that container's render scope.
3. `RenderBranch.mount` calls `attachRenderParent()`, which resolves the nearest
   `RenderParentLink` and lets that branch `adoptRenderChild(this)` — setting the parent
   pointer and propagating the binding downward.
4. A rebuild runs `performRebuild()` → `markNeedsLayout()` + `markNeedsPaint()`, the binding
   schedules a microtask frame pass, and the pass runs `owner.flush()` → flow relayout →
   repaint of the dirty rects → `grid.swap()` → ANSI to the sink.

What makes this *not* a second tree in the Flutter sense: no retained render node exists
beside the branch, and downward adjacency (`renderChildren`) is derived from `visitChildren`
on demand rather than stored. Only the upward pointer (`renderParent`) and the binding are
retained, because attach and detach need them.

## 4. Worked example — `genesis_perception`, a measurement

| Piece | What it is | Where |
|---|---|---|
| Artifacts | the mounted element itself — `PerceptionElement` subclasses: `NodeElement` (container; its rebuild hook reconciles children) and `FieldElement` (leaf; the inherited empty hook) | `packages/perception/lib/src/perception_element.dart`, `node.dart`, `field.dart` |
| Owner | none beyond the spine — `PerceptionOwner extends TreeOwner`, renaming `flush()` → `flushHarvest()` and `onNeedsFlush` → `onNeedsHarvest` | `packages/perception/lib/src/perception_owner.dart` |
| Protocol | harvest-on-read: `serializePerceptionFragment(Branch)` folds the live subtree into a JSON map | `packages/perception/lib/src/serialize.dart` |
| Affordance scope | `InheritedPerception<T>` — the domain face of `InheritedSeed<T>` | `packages/perception/lib/src/inherited_perception.dart` |

Two moves specific to a domain that wants its own vocabulary (ADR-0001 Decision 6):

- **Rename, do not re-implement.** `markNeedsHarvest` is the single domain override point:
  `PerceptionElement.markNeedsRebuild()` funnels into `markNeedsHarvest()`, which super-calls
  the tree path. Every invalidation route — direct marking and provider dependency changes
  alike — passes through the domain name, with no second dirty mechanism beside the spine's.
- **Composition stays tree-owned.** `PerceptionElement extends Branch` is reserved for
  *artifact* elements. The stateless / stateful / inherited perception classes subclass the
  tree's composition branches and only upgrade the handle — Flutter's `ComponentElement` vs
  `RenderObjectElement` split, made literal in the type hierarchy.

Perception is the proof that the four pieces are not four classes: it *is* its artifacts,
aliases its owner, pulls its protocol, and re-exports its scopes.

## 5. Worked example outside genesis — the_grid's Allocation Tree

the_grid runs its orchestrator on the spine and defines an artifact layer for *live effects*:
a spawned `claude` process, a tmux session, a federation lease, a running app
(`the_grid/docs/adr/ADR-0009-the-allocation-tree.md`, Accepted 2026-07-01).

- **Artifacts:** an `Allocation` — a persistent, addressable managed object holding one live
  effect. Held *by* a branch rather than equal to it, because the effect must survive
  re-adoption across identity.
- **Owner and protocol:** lifecycle as type properties — `startOrAdopt` / `update` /
  `dispose` / `detach` — driven by a thin synchronous host over an async effect owner.
- **Affordance scopes:** scope branches (`SessionScope`, `SubstationScope`) that create
  allocations for their subtrees.

Terminology stays per-repo: the_grid's ADR-0009 names the shape a *third tree* (the
RenderObject-analogue) and names its instance the Allocation Tree; genesis's word for the
piece is the **artifact layer**. The fact that matters to a genesis reader is the negative
one — that ADR exists *because* genesis ships none of this, and building it in the_grid left
genesis the clean substrate. The symptom it cured was live effects smeared into the branch
layer (an `initState` that fires an unawaited run loop, an `Expando` keyed by a context,
hand-managed cancel-token identity), which is anti-pattern 1 below.

## 6. The layer has no required shape

From `Branch`'s perspective the artifact layer is not a tree, or anything else in particular.
Artifacts can hang off branches individually, with every relationship carried by the branch
tree and its inherited values; or they can form their own linked structure, up to and
including a full second tree (`RenderObject`'s choice).

**Earn structure from a concrete problem.** Build a linked layer only when you can name a
relationship the branch tree cannot carry — a parent that must enumerate, meter, or re-parent
its artifacts directly. Typesetting earned exactly one retained link (`renderParent`, plus
the binding pointer) because attach and detach need it, and derives everything else on
demand. Perception earned none. Do not contort to avoid the structure, and do not build it
for Flutter-symmetry either.

## 7. Anti-patterns

1. **Putting the pass on `Branch`.** Timers, listeners, post-frame-style callbacks, and
   effect loops on the spine are exactly the accretion the purity invariant refuses
   (ADR-0001 Decision 3: "if the proposed addition is *a callback the framework calls back
   into*, it belongs in a subclass, not the spine"). The tell is state that has nowhere to
   live: an `initState` firing an unawaited run loop, an `Expando` keyed by a context, a
   hand-managed cancel token. That is an artifact layer asking to exist.
2. **A second dirty mechanism.** Your pass consumes `TreeOwner.flush()`'s return value; do
   not maintain a parallel "needs rebuild" set beside the spine's. Register your own
   *artifact* dirty set (paint, effect, resource) keyed off the flush, the way `StageBinding`
   does with its depth-sorted paint set.
3. **Making the element its own context.** That re-commits Flutter's Element≡BuildContext
   sin, which ADR-0001 Decision 2 sheds: "`Branch` does **not** implement `TreeContext`. The
   context is a *distinct capability handle* passed to `build()`, never the mounted node
   itself." Layer a handle over `TreeContext` instead (§2.4); `PerceptionContext` is the
   worked shape, and `packages/perception/lib/src/perception_element.dart` documents the
   refusal in place — "This element deliberately does NOT implement `PerceptionContext`."
4. **Reusing a child's key on a scope wrapper.** Two branches then answer to one key, and
   every key-based lookup finds both. Namespace the wrapper's key, as `_RenderScopeKey` does.
5. **Reaching into a branch's `State` from the artifact layer.** `StatefulBranch.state` is
   `@protected` — subclass-only, not public API (ADR-0001 Decision 3). Expose a narrow seam
   interface on the element and test `branch is YourSeam`, the way the action substrate does.

## 8. Checklist for a new consumer

1. **What does a branch own that outlives a rebuild?** That is your artifact set (§2.1). If
   the honest answer is "nothing", you do not need an artifact layer.
2. **Is the artifact the branch, or held by it?** Equal lifetime → be the branch; must
   survive re-adoption → hold it.
3. **Push or pull?** A pushed pass needs an owner over `TreeOwner.flush()` (§2.2); a pulled
   one needs no owner at all.
4. **What runs in the pass, in what order?** Name the phases out loud — typesetting's are
   measure, place, paint (§2.3).
5. **What must a branch read from its ancestors?** Ambient values → `InheritedSeed<T>`;
   domain capabilities → wrap `TreeContext`, never subclass a branch into one (§2.4).
6. **Can every relationship ride the branch tree?** If yes, retain no links. If no, name the
   relationship before adding one (§6).
7. **Does anything you added belong on `Branch`?** If it is a callback the framework calls
   back into, it belongs in your subclass, not the spine.
