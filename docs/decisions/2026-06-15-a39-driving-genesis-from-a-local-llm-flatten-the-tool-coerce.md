---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a39-driving-genesis-from-a-local-llm-flatten-the-tool-coerce
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A39"
---
## A39 (2026-06-15) — Driving genesis from a local LLM: flatten the tool, coerce loosely, wrap the envelope host-side  ·  AI

**Decision:** when driving genesis from a local LLM without constrained decoding (e.g. swift-infer / qwen), do NOT offer `taxonomy`'s generated full-envelope tool schema (`console.g.json`: `version → updateComponents → components[] → oneOf`) directly — the deep nesting makes local models emit malformed structure (observed live: a leaked tool-format token landing in `updateComponents`, and `components` returned as a *stringified* JSON array). Instead: offer a FLAT tool (just the `components` array, derived from the generated schema's `items` so it stays single-sourced) and have the host add the `version`/envelope/`surfaceId` and synthesize any registry-only root (e.g. typesetting's `screen`/`Stage`, which is not in the schema — A34). Pair it with a robustness layer (reparse stringified array/object values; coerce numeric-string ints for catalog `type: integer` props) and a bounded self-correction loop that feeds validation errors back as tool results. Guard the synthesized root's reserved id and the host-root container id — a stray component reusing them would silently capture the tree (the author-side twin of A38).
**Why:** validated by compiled probes against swift-infer (`qwen3.6-35b-a3b-8bit`): tool-calling works (`finish_reason: tool_calls`) but `tool_choice: required` is not enforced (auto only → a strong system prompt is required), and structural fidelity degrades with nesting depth + JSON typing. The flat contract + coercion + self-correction made a real `ask` reliably render across the six-package loop (`apps/console` v1, adversarially reviewed).
**Affects:** `genesis_taxonomy` (the generated tool schema is the *source* for the flattened tool, not a contract a local model emits directly); any agent-loop consumer (`apps/console`; a future `the_grid` agent driver); pairs with A34 (registry-only render roots) and A38 (host-reserved ids). **Status:** pending.

