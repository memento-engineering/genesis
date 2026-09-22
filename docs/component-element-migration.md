# Component/Element migration

Genesis keeps the `genesis_tree` package identity and adopts nonvisual
Component/Element vocabulary. This is an API vocabulary migration, not a move
to Jaspr or Flutter. The mounted node and build capability remain separate:
`Element` never implements `BuildContext`.

## Canonical concordance

| Previous API | Canonical API | Compatibility |
|---|---|---|
| `Seed` | `Component` | deprecated typedef |
| `Branch` | `Element` | deprecated typedef |
| `TreeContext` | `BuildContext` | deprecated typedef |
| `TreeOwner` | `BuildOwner` | deprecated typedef |
| `ComponentBranch` | `BuildableElement` | deprecated typedef |
| `StatelessSeed` / `StatelessBranch` | `StatelessComponent` / `StatelessElement` | deprecated typedefs |
| `StatefulSeed` / `StatefulBranch` | `StatefulComponent` / `StatefulElement` | deprecated typedefs |
| `InheritedSeed` / `InheritedBranch` | `InheritedComponent` / `InheritedElement` | deprecated typedefs |
| `InheritedModelSeed` / `InheritedModelBranch` | `InheritedModel` / `InheritedModelElement` | deprecated typedefs |
| `SingleChildSeed` / `SingleChildBranchMixin` | `SingleChildComponent` / `SingleChildElementMixin` | deprecated typedefs |
| `SingleChildStatelessSeed` / `SingleChildStatelessBranch` | `SingleChildStatelessComponent` / `SingleChildStatelessElement` | deprecated typedefs |
| `SingleChildStatefulSeed` / `SingleChildStatefulBranch` | `SingleChildStatefulComponent` / `SingleChildStatefulElement` | deprecated typedefs |
| `MultiChildSeed` / `MultiChildBranch` | `MultiChildComponent` / `MultiChildElement` | deprecated typedefs; remains experimental under the two-consumer rule |
| `NestBranch` | `NestElement` | deprecated typedef; `Nest` is retained |
| `Sprout` / `SproutContext` / `SproutBranch` | `HookComponent` / `HookBuildContext` / `HookElement` | deprecated typedefs |
| `RenderSeed` / `RenderBranch` | `RenderComponent` / `RenderElement` | deprecated typedefs |
| `StageBranch` / `BoxBranch` / `TextBranch` | `StageElement` / `BoxElement` / `TextElement` | deprecated typedefs |
| `SeedFactoryFn` | `ComponentFactoryFn` | deprecated typedef |
| `buildSeedTree` | `buildComponentTree` | deprecated forwarding function |

| Previous member | Canonical member | Compatibility |
|---|---|---|
| `createBranch()` | `createElement()` | reciprocal virtual forwarding preserves old- or new-style overrides |
| `Element.seed` | `Element.component` | deprecated getter |
| `State.seed` | `State.component` | deprecated getter |
| `branchId` | `elementId` | deprecated getters on elements and contexts |
| `childBranch` | `childElement` | deprecated getter |
| `rootBranch` | `rootElement` | deprecated getters on dialogue and consent surfaces |
| `runBranchBuild` | `runElementBuild` | deprecated forwarding method |
| `dependOnInheritedSeedOfExactType` | `dependOnInheritedValueOfExactType` | deprecated forwarding method |
| `getInheritedSeedOfExactType` | `getInheritedValueOfExactType` | deprecated forwarding method |
| `RenderParentLink.branch` | `RenderParentLink.element` | deprecated getter |

`ProviderTreeContext` becomes `ProviderBuildContext`. Normal extension calls
such as `context.watch<T>()` and `context.read<T>()` migrate without call-site
changes. Dart cannot expose the old explicit extension name beside the new one
without creating ambiguous extension resolution, so a call that explicitly
names `ProviderTreeContext(...)` is an unavoidable source break.

An external class declared with `implements TreeContext` must add the canonical
members (`elementId` and the inherited-value lookup verbs). A typedef preserves
interface identity but cannot synthesize renamed instance members. This is the
other bounded source break.

## Deliberately retained vocabulary

`Nest`, `Watch`, `StateCell`, `Dispose`, `TreeLifecyclePhase`,
`TreeLifecycleParticipant`, `TreeSnapshotReader`, `TreeWatchingReader`, and
`TreeDependencyScope` remain. They describe composition, attention, hook
values, or tree-wide lifecycle rather than the retired configuration/mounted
node metaphor. Perception/Node/Field and render-domain nouns remain meaningful
domain vocabulary.

The source API is `TreeNode.componentType`, but diagnostics contract version 1
continues to encode and decode the literal JSON key `seedType`. The lint codes
`no_stored_tree_context` and `use_tree_context_synchronously` also remain stable
for existing analyzer configurations while their messages name `BuildContext`.

## Package impact

| Package | Impact |
|---|---|
| `genesis_foundation` | `TreeNode.componentType`; deprecated `seedType` source bridges; stable wire key |
| `genesis_tree` | canonical spine, composition families, hooks, providers, and forwarding compatibility |
| `genesis_perception` | rebased public tree signatures; domain vocabulary and harvest behavior unchanged |
| `genesis_taxonomy` | component factories and builder; generated registries regenerated from catalogs |
| `genesis_typesetting` | render component/element descendants and parent links |
| `genesis_dialogue` | `BuildOwner`, `rootElement`, canonical keyed reconciliation |
| `genesis_consent` | fresh `Element` traversal and `rootElement`; action gates unchanged |
| `genesis_lint` | canonical and legacy context/element recognition; stable diagnostic codes |
| `genesis_console` | canonical owner, state, render, and dump terminology |

## Behavioral contract

The rename does not change runtime type identity, key matching, reparenting,
the identical-component fast path, inherited whole/aspect invalidation,
context lifetime, provider ownership, hook slot/effect order, or release-mode
guards. `BuildOwner` still tracks the element whose build hook is executing and
debug-checks that an element dirtied during that scope is its descendant,
including nested update cascades. Builds remain synchronous and effect-free.

## Bridge retirement

Compatibility bridges remain throughout this release. Removing them requires
a separately approved breaking release after first-party and known external
consumers have migrated, the migration guide has shipped for at least one
release, and a repository audit finds no compatibility use outside dedicated
probes. This release does not authorize removal.
