import '../console.dart';
import 'coerce.dart';
import 'llm_client.dart';

/// The outcome of an [Agent.ask] turn.
sealed class AgentOutcome {
  const AgentOutcome();
}

/// The model rendered/updated the surface; [summary] describes what.
class AgentRendered extends AgentOutcome {
  /// Creates a rendered outcome.
  const AgentRendered(this.summary);

  /// A short description of what was rendered.
  final String summary;
}

/// The model replied with text instead of rendering.
class AgentSaid extends AgentOutcome {
  /// Creates a text outcome.
  const AgentSaid(this.text);

  /// The model's text.
  final String text;
}

/// The model could not produce a valid render after [attempts] rounds.
class AgentFailed extends AgentOutcome {
  /// Creates a failure outcome.
  const AgentFailed(this.error, this.attempts);

  /// The last error fed back to the model.
  final String error;

  /// How many rounds were attempted.
  final int attempts;
}

/// Drives a [Console] from natural-language prompts via an [LlmClient].
///
/// Each [ask] runs a bounded self-correction loop: the model is asked to call
/// the `render` tool; its arguments are coerced into a valid `updateComponents`
/// message and applied; any coerce/validate failure is fed back as a tool
/// result so the model can fix it on the next round.
class Agent {
  /// Creates an agent driving [console] via [llm] with the given render [tool].
  Agent({
    required Console console,
    required LlmClient llm,
    required Map<String, Object?> tool,
    int maxRounds = 3,
  }) : _console = console,
       _llm = llm,
       _tool = tool,
       _maxRounds = maxRounds;

  final Console _console;
  final LlmClient _llm;
  final Map<String, Object?> _tool;
  final int _maxRounds;

  /// Asks the model to render/update the screen for [prompt].
  Future<AgentOutcome> ask(String prompt) async {
    final messages = <ChatMessage>[SystemMessage(_systemPrompt)];
    final mounted = _console.surfaceId != null;
    messages.add(
      UserMessage(
        mounted ? '$prompt\n\nCurrent screen:\n${_console.snapshot()}' : prompt,
      ),
    );

    var lastError = 'the model did not produce a valid render';
    for (var round = 0; round < _maxRounds; round++) {
      final result = await _llm.chat(messages, tool: _tool);
      switch (result) {
        case LlmText(:final content):
          return AgentSaid(content);
        case LlmToolCall(:final id, :final name, :final arguments):
          if (name != 'render') {
            // Only one tool is offered; an off-name call is a model error.
            lastError = 'unknown tool "$name" — call the "render" tool';
            _feedBack(messages, id, name, arguments, lastError);
          } else {
            try {
              final message = toUpdateComponents(arguments);
              await _console.loadOrApply(message);
              final components =
                  (message['updateComponents']!
                          as Map<String, Object?>)['components']!
                      as List<Object?>;
              // Subtract the synthesised screen root from the count.
              final n = components.length - 1;
              return AgentRendered('rendered $n component${n == 1 ? '' : 's'}');
            } on Object catch (error) {
              lastError = error is FormatException
                  ? error.message
                  : error.toString();
              _feedBack(
                messages,
                id,
                name,
                arguments,
                'ERROR: $lastError\nFix the arguments and call render again. '
                'Remember: a flat array; integers are JSON numbers; the top '
                'container is a box with id "content".',
              );
            }
          }
      }
    }
    return AgentFailed(lastError, _maxRounds);
  }

  /// Replays the assistant's tool call and appends a tool result carrying
  /// [content] — a valid OpenAI tool-result sequence the model can act on.
  void _feedBack(
    List<ChatMessage> messages,
    String id,
    String name,
    String arguments,
    String content,
  ) {
    messages
      ..add(ToolCallMessage(id: id, name: name, arguments: arguments))
      ..add(ToolResultMessage(id: id, content: content));
  }

  static const String _systemPrompt = '''
You drive a terminal UI by calling the `render` tool. ALWAYS call `render` — never reply with prose.
Emit a FLAT array of components (an adjacency list); a container lists its children by id.
Component types:
- "box": a titled container. Props: title (string), children (array of ids).
- "counter": an interactive counter. Props: label (string), start (integer). Affords the press and set actions.
- "text": a line of text. Props: content (string).
Rules:
- Your top-level container MUST be a box with id "content". Do NOT emit a component with id "root" — the host adds it.
- Every id must be unique and stable; re-emit the same id to update a component in place.
- Integers (e.g. start) MUST be JSON numbers, never strings.
- Emit the WHOLE component tree every time; the client reconciles by id.''';
}
