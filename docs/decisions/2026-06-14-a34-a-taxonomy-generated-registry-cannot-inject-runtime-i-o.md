---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a34-a-taxonomy-generated-registry-cannot-inject-runtime-i-o
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A34"
---
## A34 (2026-06-14) — A taxonomy-generated registry cannot inject runtime I/O for a render root; compose a superset registry  ·  AI

**Decision:** a render-owner type whose seed needs runtime I/O (e.g. `Stage`, which requires a `Sink<List<int>>` with no wire representation) must NOT be a `taxonomy` catalog type — codegen emits `Stage(width,height,children,key)` missing `sink`, which does not compile. Sanctioned shape: generate the non-I/O types, then compose a superset `ComponentRegistry` at runtime — `{...generated.entries, '<render-root>': RegistryEntry(build: <closure capturing sink/dims>)}` — via the public `ComponentRegistry.entries` map + `RegistryEntry`'s public const ctor.
**Why:** the only verified mechanism to supply the sink is a hand-written factory closing over it lexically (de-risk render spike); the merge preserves the generator-in-sync guarantee for every type except the hand-wired render root.
**Affects:** `genesis_taxonomy` (`ComponentRegistry`/`RegistryEntry` as a sanctioned public composition surface, beyond "generated code is the only caller"); `genesis_typesetting` (`Stage`'s required runtime sink); apps/console registry assembly. **Status:** pending.

