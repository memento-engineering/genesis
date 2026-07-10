import 'dart:convert';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:genesis_console/genesis_console.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:test/test.dart';

/// Wire-translation tests for [SwiftInferClient].
///
/// The genai_primitives adoption (register A26/A42) kept the OpenAI
/// `/v1/chat/completions` encode/decode as the client's own concern: genai is
/// the in-memory model, the wire shape is translated here. A [MockClient]
/// captures the request body (so we can assert `_encode`/tool render) and
/// returns canned replies (so we can assert the decode + A39 lenient argument
/// parsing) — no swift-infer server needed.
void main() {
  const config = AgentConfig(
    baseUrl: 'http://localhost:8080',
    model: 'test-model',
    agentToken: 'secret-token',
  );

  // A tool with a real input schema, so the render can be asserted 1:1.
  final tool = ToolDefinition(
    name: 'render',
    description: 'render a surface',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'components': {'type': 'array'},
      },
      'required': ['components'],
    }),
  );

  // A client whose HTTP layer returns [body] as JSON with [status], recording
  // every request into the returned list for encode assertions.
  (SwiftInferClient, List<http.Request>) clientReturning(
    Object body, {
    int status = 200,
  }) {
    final log = <http.Request>[];
    final mock = MockClient((request) async {
      log.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return (SwiftInferClient(config, httpClient: mock), log);
  }

  // The messages array of the single captured request.
  List<Object?> encodedMessages(List<http.Request> log) =>
      (jsonDecode(log.single.body) as Map<String, Object?>)['messages']
          as List<Object?>;

  // A canned content-only OpenAI reply (the request is what's under test).
  Object contentReply(String content) => {
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  };

  group('request encoding', () {
    test('system/user/model text encode to their OpenAI roles', () async {
      final (client, log) = clientReturning(contentReply('ok'));
      await client.chat([
        ChatMessage.system('you are a renderer'),
        ChatMessage.user('show apples'),
        ChatMessage.model('working on it'),
      ], tool: tool);

      expect(encodedMessages(log), [
        {'role': 'system', 'content': 'you are a renderer'},
        {'role': 'user', 'content': 'show apples'},
        {'role': 'assistant', 'content': 'working on it'},
      ]);
    });

    test('the model, token, and tool_choice ride the request', () async {
      final (client, log) = clientReturning(contentReply('ok'));
      await client.chat([ChatMessage.user('hi')], tool: tool);

      final body = jsonDecode(log.single.body) as Map<String, Object?>;
      expect(body['model'], 'test-model');
      expect(body['tool_choice'], 'auto');
      expect(log.single.headers['authorization'], 'Bearer secret-token');
      expect(
        log.single.url.toString(),
        'http://localhost:8080/v1/chat/completions',
      );
    });

    test('a model tool-call encodes to an assistant tool_calls entry', () async {
      final (client, log) = clientReturning(contentReply('ok'));
      await client.chat([
        ChatMessage.model(
          '',
          parts: [
            ToolPart.call(
              callId: 'call_7',
              toolName: 'render',
              arguments: {
                'components': [1, 2],
              },
            ),
          ],
        ),
      ], tool: tool);

      // arguments ride the wire as a JSON *string* (OpenAI's shape), not a map.
      expect(encodedMessages(log).single, {
        'role': 'assistant',
        'tool_calls': [
          {
            'id': 'call_7',
            'type': 'function',
            'function': {
              'name': 'render',
              'arguments': jsonEncode({
                'components': [1, 2],
              }),
            },
          },
        ],
      });
    });

    test(
      'a tool-result rides a user message but encodes to the tool role',
      () async {
        // genai has no `tool` role; the agent carries a result on a user-role
        // ChatMessage, which must land as OpenAI's dedicated `tool` message.
        final (client, log) = clientReturning(contentReply('ok'));
        await client.chat([
          ChatMessage.user(
            '',
            parts: [
              ToolPart.result(
                callId: 'call_7',
                toolName: 'render',
                result: 'ERROR: missing components',
              ),
            ],
          ),
        ], tool: tool);

        expect(encodedMessages(log).single, {
          'role': 'tool',
          'tool_call_id': 'call_7',
          'content': 'ERROR: missing components',
        });
      },
    );

    test(
      'the tool renders to an OpenAI function carrying its input schema',
      () async {
        final (client, log) = clientReturning(contentReply('ok'));
        await client.chat([ChatMessage.user('hi')], tool: tool);

        final tools =
            (jsonDecode(log.single.body) as Map<String, Object?>)['tools']
                as List<Object?>;
        expect(tools.single, {
          'type': 'function',
          'function': {
            'name': 'render',
            'description': 'render a surface',
            'parameters': tool.inputSchema.value,
          },
        });
      },
    );
  });

  group('response decoding', () {
    // A canned OpenAI reply whose single tool_call carries [rawArguments]
    // verbatim as its arguments string.
    Object toolCallReply(String rawArguments, {String id = 'call_9'}) => {
      'choices': [
        {
          'message': {
            'tool_calls': [
              {
                'id': id,
                'function': {'name': 'render', 'arguments': rawArguments},
              },
            ],
          },
        },
      ],
    };

    test('a tool_calls reply decodes to a model tool-call message', () async {
      final (client, _) = clientReturning(
        toolCallReply(
          jsonEncode({
            'components': [
              {'id': 'x'},
            ],
          }),
        ),
      );
      final reply = await client.chat([ChatMessage.user('show')], tool: tool);

      expect(reply.hasToolCalls, isTrue);
      final call = reply.toolCalls.single;
      expect(call.callId, 'call_9');
      expect(call.toolName, 'render');
      expect(call.arguments, {
        'components': [
          {'id': 'x'},
        ],
      });
    });

    test(
      'a double-encoded arguments blob still decodes to a map (A39)',
      () async {
        // A local model without constrained decoding wraps the args JSON in a
        // second JSON string: the outer decode yields a String, the inner a map.
        final singleEncoded = jsonEncode({
          'components': [1],
        });
        final (client, _) = clientReturning(
          toolCallReply(jsonEncode(singleEncoded)),
        );
        final reply = await client.chat([ChatMessage.user('show')], tool: tool);

        expect(reply.toolCalls.single.arguments, {
          'components': [1],
        });
      },
    );

    test('unrecoverable arguments decode to {} rather than throwing', () async {
      // Garbage the coercer will later reject with a fed-back error, not a throw
      // here — the malformed call must still reach the self-correction loop.
      final (client, _) = clientReturning(toolCallReply('not json at all'));
      final reply = await client.chat([ChatMessage.user('show')], tool: tool);

      expect(reply.hasToolCalls, isTrue);
      expect(reply.toolCalls.single.arguments, isEmpty);
    });

    test('a tool_call missing its id falls back to call_0', () async {
      final (client, _) = clientReturning({
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'function': {'name': 'render', 'arguments': '{}'},
                },
              ],
            },
          },
        ],
      });
      final reply = await client.chat([ChatMessage.user('show')], tool: tool);

      expect(reply.toolCalls.single.callId, 'call_0');
    });

    test('a content-only reply decodes to a model text message', () async {
      final (client, _) = clientReturning(contentReply('I cannot do that.'));
      final reply = await client.chat([ChatMessage.user('hi')], tool: tool);

      expect(reply.hasToolCalls, isFalse);
      expect(reply.text, 'I cannot do that.');
    });

    test('a null content reply decodes to empty text', () async {
      final (client, _) = clientReturning({
        'choices': [
          {'message': <String, Object?>{}},
        ],
      });
      final reply = await client.chat([ChatMessage.user('hi')], tool: tool);

      expect(reply.hasToolCalls, isFalse);
      expect(reply.text, isEmpty);
    });

    test('a non-200 response throws LlmException', () async {
      final (client, _) = clientReturning({'error': 'nope'}, status: 500);
      await expectLater(
        () => client.chat([ChatMessage.user('hi')], tool: tool),
        throwsA(isA<LlmException>()),
      );
    });

    test('an empty choices list throws LlmException', () async {
      final (client, _) = clientReturning({'choices': <Object?>[]});
      await expectLater(
        () => client.chat([ChatMessage.user('hi')], tool: tool),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
