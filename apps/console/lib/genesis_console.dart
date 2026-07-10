/// The genesis console: a terminal driver that renders an A2UI v0.9 surface to
/// a character grid, enforces client actions across the genesis stack (tree,
/// taxonomy, typesetting, dialogue, consent), and drives it from natural
/// language via a swift-infer agent.
library;

export 'package:genesis_consent/genesis_consent.dart'
    show Applied, ConsentOutcome, Rejected, RejectionKind, ActionChange;
export 'package:genesis_dialogue/genesis_dialogue.dart' show ActionEvent;

export 'src/agent/agent.dart';
export 'src/agent/coerce.dart' show toUpdateComponents;
export 'src/agent/config.dart';
// The conversation/tool vocabulary on the LlmClient contract is genai_primitives'
// ChatMessage/Part/ToolDefinition (register A26/A42) — a consumer implementing a
// custom LlmClient imports that package directly rather than through this barrel.
export 'src/agent/llm_client.dart'
    show LlmClient, SwiftInferClient, LlmException;
export 'src/agent/tool_schema.dart';
export 'src/console.dart';
export 'src/counter.dart';
export 'src/registry.dart';
