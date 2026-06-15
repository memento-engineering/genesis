import 'dart:convert';

import 'package:genesis_console/genesis_console.dart';
// The ChatMessage wire family is intentionally not re-exported by the barrel
// (it is internal); the fake client and assertions reach it directly.
import 'package:genesis_console/src/agent/llm_client.dart'
    show ChatMessage, ToolCallMessage, ToolResultMessage;
import 'package:test/test.dart';

/// A canned [LlmClient]: returns queued results in order (clamping to the last)
/// and records every message list it received, so tests can assert the
/// self-correction loop fed an error back.
class FakeLlmClient implements LlmClient {
  FakeLlmClient(this._results);

  final List<LlmResult> _results;
  int _index = 0;

  /// The messages passed to each [chat] call, in order.
  final List<List<ChatMessage>> received = [];

  @override
  Future<LlmResult> chat(
    List<ChatMessage> messages, {
    required Map<String, Object?> tool,
  }) async {
    received.add(List.of(messages));
    final result = _results[_index.clamp(0, _results.length - 1)];
    _index++;
    return result;
  }
}

void main() {
  late _Sink sink;
  late Console console;

  setUp(() async {
    sink = _Sink();
    console = await Console.create(sink: sink);
  });

  // A render tool-call whose arguments wrap [components] (a List or a String).
  LlmToolCall render(Object components) => LlmToolCall(
    id: 'call_0',
    name: 'render',
    arguments: jsonEncode({'components': components}),
  );

  List<Object?> tree({Object start = 3}) => [
    {
      'id': 'content',
      'component': 'box',
      'title': 'Demo',
      'children': ['c1'],
    },
    {'id': 'c1', 'component': 'counter', 'label': 'Apples', 'start': start},
  ];

  Agent agentWith(List<LlmResult> results) => Agent(
    console: console,
    llm: FakeLlmClient(results),
    tool: const {'type': 'function'},
  );

  test('a clean tool call renders the surface', () async {
    final outcome = await agentWith([render(tree())]).ask('show apples');
    expect(outcome, isA<AgentRendered>());
    expect(console.snapshot(), contains('Apples: 3'));
    expect(console.surfaceId, 'console');
  });

  test('a stringified components array still renders', () async {
    // The exact malformed shape observed live: components as a JSON string.
    final outcome = await agentWith([render(jsonEncode(tree()))]).ask('show');
    expect(outcome, isA<AgentRendered>());
    expect(console.snapshot(), contains('Apples: 3'));
  });

  test('a numeric-string start is coerced and renders as an int', () async {
    final outcome = await agentWith([render(tree(start: '7'))]).ask('show');
    expect(outcome, isA<AgentRendered>());
    expect(console.snapshot(), contains('Apples: 7'));
  });

  test('a malformed first call is fixed on retry (error fed back)', () async {
    final fake = FakeLlmClient([
      render([
        {'id': 'oops', 'component': 'box', 'title': 'no content id'},
      ]),
      render(tree()),
    ]);
    final agent = Agent(
      console: console,
      llm: fake,
      tool: const {'type': 'function'},
    );

    final outcome = await agent.ask('show apples');
    expect(outcome, isA<AgentRendered>());
    expect(console.snapshot(), contains('Apples: 3'));
    // The second round must have replayed the bad call + an error tool result.
    expect(fake.received.length, 2);
    // The fed-back round must replay the assistant tool_call BEFORE its tool
    // result — an orphan tool result is an invalid sequence swift-infer rejects.
    final call = fake.received[1].whereType<ToolCallMessage>().single;
    expect(call.id, 'call_0');
    expect(
      fake.received[1].whereType<ToolResultMessage>().single.content,
      contains('content'),
    );
  });

  test(
    'a persistently malformed model fails after maxRounds, no crash',
    () async {
      final bad = render([
        {'id': 'oops', 'component': 'box', 'title': 'never has content'},
      ]);
      final fake = FakeLlmClient([bad, bad, bad]);
      final agent = Agent(
        console: console,
        llm: fake,
        tool: const {'type': 'function'},
      );
      final outcome = await agent.ask('show');
      expect(outcome, isA<AgentFailed>());
      expect((outcome as AgentFailed).attempts, 3);
      // Pin the REAL round count so a reduced-rounds regression fails
      // (attempts is the maxRounds constant, not a live counter).
      expect(fake.received.length, 3, reason: 'looped maxRounds times');
      expect(console.surfaceId, isNull, reason: 'nothing was mounted');
    },
  );

  test('a text-only reply surfaces as AgentSaid', () async {
    final outcome = await agentWith([
      const LlmText('I cannot do that.'),
    ]).ask('hello');
    expect(outcome, isA<AgentSaid>());
    expect((outcome as AgentSaid).text, contains('cannot'));
  });

  test('a second ask updates the live surface (reconcile by id)', () async {
    final agent = agentWith([
      render(tree()),
      render([
        {
          'id': 'content',
          'component': 'box',
          'title': 'Demo',
          'children': ['c1'],
        },
        // Same id c1, new label. start is ignored on reconcile (A9: the live
        // count is preserved), so the label updates while the count stays 3.
        {'id': 'c1', 'component': 'counter', 'label': 'Bananas', 'start': 0},
      ]),
    ]);
    await agent.ask('show apples');
    expect(console.snapshot(), contains('Apples: 3'));
    await agent.ask('relabel to bananas');
    final grid = console.snapshot();
    expect(grid, contains('Bananas: 3'), reason: 'reconcile updated the label');
    expect(grid, isNot(contains('Apples')), reason: 'old label replaced');
  });
}

/// A byte sink that discards frames — these tests assert on the grid snapshot.
class _Sink implements Sink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void close() {}
}
