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
// The ChatMessage wire family is internal to the SwiftInferClient<->LlmClient
// contract; consumers driving the Agent need only the interface + result types.
export 'src/agent/llm_client.dart'
    show
        LlmClient,
        LlmResult,
        LlmToolCall,
        LlmText,
        SwiftInferClient,
        LlmException;
export 'src/agent/tool_schema.dart';
export 'src/console.dart';
export 'src/counter.dart';
export 'src/registry.dart';
