---
status: accepted
date: 2026-07-10
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a42-adopt-genai-primitives-for-the-agent-loop-conversation-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A42"
---
## A42 (2026-07-10) — Adopt `genai_primitives` for the agent-loop conversation/tool vocabulary (as built)  ·  AI

**Context:** A26 item 4 said "when the model↔genesis agent loop is built, **adopt** flutter/genui's `genai_primitives` (`ChatMessage`/`Part`/`ToolDefinition`), don't invent" the conversation/tool vocabulary. The loop is now built (`apps/console`, A39), and it had invented exactly that vocabulary — a `sealed ChatMessage` with `SystemMessage`/`UserMessage`/`ToolCallMessage`/`ToolResultMessage`, a parallel `LlmResult`/`LlmToolCall`/`LlmText` reply hierarchy, and a hand-built OpenAI tool `Map`. This entry records the trigger firing.

**Decision (as built; console 35 tests green, full workspace green: tree 203 / perception 109 / taxonomy 73 / typesetting 28 / dialogue 38 / consent 16 / tmux 75 / console 35; analyze + format clean):**
- **Replaced the invented vocabulary with `genai_primitives`** (`0.2.3`, pure-Dart, VM-safe, BSD-3, `labs.flutter.dev`): the invented `ChatMessage` family + `LlmResult` hierarchy are **deleted**; the conversation is `List<ChatMessage>` (`.system`/`.user`/`.model`), tool calls/results are `ToolPart.call`/`ToolPart.result` parts, and the tool is a `ToolDefinition`.
- **`LlmClient.chat(List<ChatMessage>, {required ToolDefinition tool}) → ChatMessage`** — the return IS the model turn; the agent branches on `reply.hasToolCalls` / `reply.toolCalls.first` / `reply.text`. The separate `LlmResult`/`LlmToolCall`/`LlmText` types are gone (`ChatMessage` + `ToolPart` subsume them). `LlmException` and `SwiftInferClient` stay genesis-native (swift-infer transport).
- **`genai_primitives` is adopted as the in-memory model ONLY; the OpenAI `/v1/chat/completions` wire encoding stays `SwiftInferClient`'s own.** genai's `toJson` is a *different* interchange format (roles system/user/model, parts tagged `Text`/`Tool`), not the OpenAI wire — so `_encode(ChatMessage)` translates by role + part kind (system→system, user→user, model+toolCalls→`assistant`/`tool_calls`, and — since genai has **no `tool` role** — a tool result rides a **user-role** `ChatMessage` carrying `ToolPart.result` and encodes to OpenAI's `{role:'tool', tool_call_id, content}`).
- **`renderTool()` now returns a `ToolDefinition`** (`inputSchema` = `Schema.fromMap` over the generated `console.g.json` `components` schema — still single-sourced from the catalog per A39); `SwiftInferClient` renders it to the OpenAI `function`-tool shape (`inputSchema.value` → `parameters`).
- **A39 self-correction robustness preserved:** OpenAI delivers tool arguments as a JSON string, so `SwiftInferClient._decodeArgs` decodes leniently (incl. a double-encoded blob) to a `Map` before building `ToolPart.call`; inner-value quirks (a stringified `components` array, numeric-string ints) remain `coerce`'s job; unrecoverable garbage → `{}` → the coercer's "missing components" error is fed back through the same bounded loop. `coerce.dart` is unchanged.
- **Dependencies added to `apps/console` only** (`genai_primitives ^0.2.3`, `json_schema_builder ^0.1.5` — the latter backs `ToolDefinition.inputSchema`, and is A26 item 3's ecosystem-aligned schema lib used minimally). **`apps/console` is `publish_to: none`**, which is precisely why a pre-1.0/-wip dependency is acceptable here — no published `genesis_*` package depends on either; the adoption sits in the driver app, exactly the scoping A26 item 4 anticipated.

**Maturity (track — A26's standing caveat):** `genai_primitives` is `0.2.3` (`0.2.4-wip` at HEAD), pre-1.0. The blast radius is contained: it lives only in the unpublished console, the surface consumed is small (`ChatMessage`/`ToolPart`/`ToolDefinition`), and every wire concern is translated at one seam (`SwiftInferClient`), so an upstream breaking change is a localized edit. Revisit at ≥1.0 (parallels the a2ui_core-at-≥1.0 collapse plan, A26 item 2).

**Affects:** `apps/console` (`lib/src/agent/llm_client.dart`, `agent.dart`, `tool_schema.dart`, `genesis_console.dart` barrel, `pubspec.yaml`, `test/agent_test.dart`); executes A26 item 4 (and touches item 3). No substrate change — this is app-layer, so ADR-0001..0006 are untouched; ADR-0003's interop note (A26) is the home if Nico promotes. **Status:** pending.

