import 'dart:convert';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// Sends a chat exchange to an LLM and returns the model's reply.
///
/// The conversation and tool vocabulary is flutter/genui's `genai_primitives`
/// ([ChatMessage] / [StandardPart] / [ToolDefinition]) — adopted, not invented
/// (register A26/A42). That package is the *in-memory* model only; the OpenAI
/// `/v1/chat/completions` wire encoding (roles, `tool_calls`, tool results)
/// stays a [SwiftInferClient] concern — `genai_primitives`' own `toJson` is a
/// different interchange format, not the OpenAI wire.
abstract interface class LlmClient {
  /// Sends [messages] with a single [tool] available and returns the model's
  /// reply message — a tool call ([ChatMessage.hasToolCalls]) and/or text.
  Future<ChatMessage> chat(
    List<ChatMessage> messages, {
    required ToolDefinition tool,
  });
}

/// Thrown when the swift-infer server returns an error or an unusable reply.
class LlmException implements Exception {
  /// Creates an exception with [message].
  const LlmException(this.message);

  /// The failure detail.
  final String message;

  @override
  String toString() => 'LlmException: $message';
}

/// An [LlmClient] backed by a swift-infer OpenAI-compatible server.
class SwiftInferClient implements LlmClient {
  /// Creates a client for [config]; inject an [httpClient] in tests.
  SwiftInferClient(this._config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final AgentConfig _config;
  final http.Client _http;

  @override
  Future<ChatMessage> chat(
    List<ChatMessage> messages, {
    required ToolDefinition tool,
  }) async {
    final body = <String, Object?>{
      'model': _config.model,
      'temperature': 0.2,
      'max_tokens': 1536,
      'messages': [for (final m in messages) _encode(m)],
      'tools': [_toolWire(tool)],
      'tool_choice': 'auto',
    };
    final response = await _http.post(
      Uri.parse('${_config.baseUrl}/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${_config.agentToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw LlmException('swift-infer HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final choices = json['choices'] as List<Object?>?;
    if (choices == null || choices.isEmpty) {
      throw const LlmException('response had no choices');
    }
    final message =
        (choices.first as Map<String, Object?>)['message']
            as Map<String, Object?>;
    final toolCalls = message['tool_calls'] as List<Object?>?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      // The model turn is a genai `ChatMessage` (role model) whose parts are the
      // tool calls it requested.
      return ChatMessage.model(
        '',
        parts: [
          for (final call in toolCalls)
            _toolPartFromWire(call as Map<String, Object?>),
        ],
      );
    }
    return ChatMessage.model((message['content'] as String?) ?? '');
  }

  /// A genai [ToolDefinition] rendered as an OpenAI `function` tool. The tool's
  /// JSON-Schema `inputSchema` becomes the function `parameters`.
  Map<String, Object?> _toolWire(ToolDefinition tool) => {
    'type': 'function',
    'function': {
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.inputSchema.value,
    },
  };

  /// A wire `tool_call` → a genai [ToolPart] call, decoding its arguments.
  ToolPart _toolPartFromWire(Map<String, Object?> call) {
    final fn = call['function'] as Map<String, Object?>;
    return ToolPart.call(
      callId: (call['id'] as String?) ?? 'call_0',
      toolName: (fn['name'] as String?) ?? '',
      arguments: _decodeArgs((fn['arguments'] as String?) ?? ''),
    );
  }

  /// OpenAI delivers tool arguments as a JSON string. Decode leniently — a
  /// local model without constrained decoding may double-encode the blob — so
  /// that malformed-but-recoverable calls still reach the agent's
  /// self-correction loop as a map rather than throwing here (register A39).
  /// Inner-value quirks (a stringified `components` array, numeric-string ints)
  /// are left to `coerce`; unrecoverable garbage decodes to `{}`, which the
  /// coercer rejects with a fed-back "missing components" error.
  Map<String, Object?> _decodeArgs(String raw) {
    Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (value is String) {
      // A doubly-encoded arguments blob: the outer decode yields a JSON string.
      try {
        value = jsonDecode(value);
      } on FormatException {
        return {};
      }
    }
    return value is Map ? value.cast<String, Object?>() : {};
  }

  /// A genai [ChatMessage] → one OpenAI wire message.
  ///
  /// genai's own `toJson` is a different interchange format (roles
  /// system/user/model, parts tagged `Text`/`Tool`), so the OpenAI shape is
  /// translated by role + part kind. The agent constructs single-purpose
  /// messages (one tool call, or one tool result, or plain text), so a 1:1
  /// mapping is exact; the first tool result wins if a message carried several.
  Map<String, Object?> _encode(ChatMessage m) {
    if (m.hasToolCalls) {
      return {
        'role': 'assistant',
        'tool_calls': [
          for (final t in m.toolCalls)
            {
              'id': t.callId,
              'type': 'function',
              'function': {'name': t.toolName, 'arguments': t.argumentsRaw},
            },
        ],
      };
    }
    if (m.hasToolResults) {
      // genai has no `tool` role; a result rides a user-role message carrying a
      // `ToolPart.result`, and encodes to OpenAI's dedicated `tool` message.
      final t = m.toolResults.first;
      return {
        'role': 'tool',
        'tool_call_id': t.callId,
        'content': t.result?.toString() ?? '',
      };
    }
    return {'role': _wireRole(m.role), 'content': m.text};
  }

  String _wireRole(ChatMessageRole role) => switch (role) {
    ChatMessageRole.system => 'system',
    ChatMessageRole.user => 'user',
    ChatMessageRole.model => 'assistant',
  };

  /// Closes the underlying HTTP client.
  void close() => _http.close();
}
