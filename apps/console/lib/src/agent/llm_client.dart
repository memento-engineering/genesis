import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// One message in a chat exchange — the subset the agent loop needs.
sealed class ChatMessage {
  const ChatMessage();
}

/// The system prompt steering the model.
class SystemMessage extends ChatMessage {
  /// Creates a system message with [content].
  const SystemMessage(this.content);

  /// The system prompt text.
  final String content;
}

/// A user turn.
class UserMessage extends ChatMessage {
  /// Creates a user message with [content].
  const UserMessage(this.content);

  /// The user text.
  final String content;
}

/// An assistant turn that called a tool — replayed so the model sees its own
/// prior (rejected) call when an error is fed back.
class ToolCallMessage extends ChatMessage {
  /// Creates a replayed assistant tool call.
  const ToolCallMessage({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The tool call id (correlates with a [ToolResultMessage]).
  final String id;

  /// The tool name.
  final String name;

  /// The raw arguments JSON string the model produced.
  final String arguments;
}

/// The result of a tool call fed back to the model (e.g. a validation error).
class ToolResultMessage extends ChatMessage {
  /// Creates a tool result for the call [id].
  const ToolResultMessage({required this.id, required this.content});

  /// The id of the tool call this answers.
  final String id;

  /// The result content (an error string, in the self-correction loop).
  final String content;
}

/// The model's reply: a tool call or plain text.
sealed class LlmResult {
  const LlmResult();
}

/// The model called a tool.
class LlmToolCall extends LlmResult {
  /// Creates a tool-call result.
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The tool call id.
  final String id;

  /// The tool name.
  final String name;

  /// The raw arguments JSON string (may be malformed — the caller coerces it).
  final String arguments;
}

/// The model replied with text instead of calling a tool.
class LlmText extends LlmResult {
  /// Creates a text result.
  const LlmText(this.content);

  /// The reply text.
  final String content;
}

/// Sends a chat exchange to an LLM and returns its reply.
abstract interface class LlmClient {
  /// Sends [messages] with a single [tool] available and returns the reply.
  Future<LlmResult> chat(
    List<ChatMessage> messages, {
    required Map<String, Object?> tool,
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
  Future<LlmResult> chat(
    List<ChatMessage> messages, {
    required Map<String, Object?> tool,
  }) async {
    final body = <String, Object?>{
      'model': _config.model,
      'temperature': 0.2,
      'max_tokens': 1536,
      'messages': [for (final m in messages) _encode(m)],
      'tools': [tool],
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
      final call = toolCalls.first as Map<String, Object?>;
      final fn = call['function'] as Map<String, Object?>;
      return LlmToolCall(
        id: (call['id'] as String?) ?? 'call_0',
        name: (fn['name'] as String?) ?? '',
        arguments: (fn['arguments'] as String?) ?? '',
      );
    }
    return LlmText((message['content'] as String?) ?? '');
  }

  Map<String, Object?> _encode(ChatMessage m) => switch (m) {
    SystemMessage(:final content) => {'role': 'system', 'content': content},
    UserMessage(:final content) => {'role': 'user', 'content': content},
    ToolCallMessage(:final id, :final name, :final arguments) => {
      'role': 'assistant',
      'tool_calls': [
        {
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': arguments},
        },
      ],
    },
    ToolResultMessage(:final id, :final content) => {
      'role': 'tool',
      'tool_call_id': id,
      'content': content,
    },
  };

  /// Closes the underlying HTTP client.
  void close() => _http.close();
}
