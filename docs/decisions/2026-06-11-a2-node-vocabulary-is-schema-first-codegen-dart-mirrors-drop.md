---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a2-node-vocabulary-is-schema-first-codegen-dart-mirrors-drop
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A2"
---
## A2 (2026-06-11) — Node vocabulary is schema-first + codegen; `dart:mirrors` dropped  ·  decider: Nico

*(migrated from lenny A1)*
**Decision:** the `tree`/`perception` node catalog is defined as **schemas**; **codegen** emits the Dart factory registry + per-node JSON/tool schemas. No `dart:mirrors` anywhere; runs unchanged on every Dart target (VM, AOT, web).
**Why:** mirrors are unavailable under Flutter/AOT and semi-abandoned; macros cancelled. A codegen'd registry is the only path uniform across all Dart targets that stays tree-shakeable. One schema is simultaneously the Dart factory registry and the LLM tool/JSON schema.
**Affects:** a `tree_codegen` (or build_runner config); the extension-contract registration (lenny register A1); the conventions baseline (A6). **Status:** promoted → ADR-0002 (ratified Nico 2026-06-11).

