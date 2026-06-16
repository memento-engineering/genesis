import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genesis_console/genesis_console.dart';

/// The genesis console REPL.
///
/// `dart run genesis_console:console` for an interactive session, or
/// `--script FILE` to run a newline-delimited command list (the offline demo).
/// `--model <id>` overrides the swift-infer model the `ask` agent uses.
/// See the `help` command (and [_help]) for the command set.
Future<void> main(List<String> args) async {
  // The REPL redraws a full grid snapshot after each command, so the surface
  // diff stream is discarded — display does not depend on the ANSI bytes.
  final console = await Console.create(sink: _DiscardSink());

  // The live agent is optional: if no swift-infer token is configured, the
  // offline commands still work and `ask` reports how to enable it. `--model
  // <id>` overrides the swift-infer model for this run.
  final modelArg = _flagValue(args, '--model');
  Agent? agent;
  var agentReason = '';
  String? agentModel;
  try {
    final config = await AgentConfig.resolve(modelOverride: modelArg);
    agentModel = config.model;
    agent = Agent(
      console: console,
      llm: SwiftInferClient(config),
      tool: await renderTool(),
    );
  } on Object catch (error) {
    agentReason = error.toString();
  }

  final scriptIdx = args.indexOf('--script');
  if (scriptIdx != -1 && scriptIdx + 1 < args.length) {
    final file = File(args[scriptIdx + 1]);
    final base = file.parent;
    for (final line in await file.readAsLines()) {
      await _run(console, agent, agentReason, line, base);
    }
    return;
  }

  stdout.writeln(_help);
  stdout.writeln(
    agent != null ? 'agent ready · model: $agentModel' : 'ask: $agentReason',
  );
  stdout.write('> ');
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (!await _run(console, agent, agentReason, line, Directory.current)) {
      break;
    }
    stdout.write('> ');
  }
}

Future<bool> _run(
  Console console,
  Agent? agent,
  String agentReason,
  String raw,
  Directory base,
) async {
  final line = raw.trim();
  if (line.isEmpty || line.startsWith('#')) return true;
  final parts = line.split(RegExp(r'\s+'));
  final cmd = parts.first;
  stdout.writeln('\n\$ $line');
  try {
    switch (cmd) {
      case 'load':
      case 'apply':
        final path = '${base.path}${Platform.pathSeparator}${parts[1]}';
        final json = jsonDecode(await File(path).readAsString()) as Object;
        await console.loadOrApply(json);
        stdout.writeln(console.snapshot());
      case 'press':
        // An unparseable amount is forwarded raw (not silently dropped to the
        // +1 default), so the counter rejects it as a badPayload — mirroring
        // how `set` forwards a non-integer value below.
        final Object? amount = parts.length > 2
            ? (int.tryParse(parts[2]) ?? parts[2])
            : null;
        final outcome = await console.route(
          ActionEvent(
            name: 'press',
            surfaceId: console.surfaceId ?? '',
            sourceComponentId: parts[1],
            payload: {if (amount != null) 'amount': amount},
          ),
        );
        _printOutcome(outcome);
        stdout.writeln(console.snapshot());
      case 'set':
        final kv = parts[2].split('=');
        final raw = kv.length > 1 ? kv[1] : '';
        // A non-integer value stays a string, so the counter rejects it as a
        // badPayload — exactly what `set c1 value=oops` should demonstrate.
        final Object value = int.tryParse(raw) ?? raw;
        final outcome = await console.route(
          ActionEvent(
            name: 'set',
            surfaceId: console.surfaceId ?? '',
            sourceComponentId: parts[1],
            payload: {kv.first: value},
          ),
        );
        _printOutcome(outcome);
        stdout.writeln(console.snapshot());
      case 'ask':
        final prompt = line.substring(cmd.length).trim();
        if (prompt.isEmpty) {
          stdout.writeln('usage: ask <prompt>');
        } else if (agent == null) {
          stdout.writeln('ask unavailable: $agentReason');
        } else {
          final outcome = await agent.ask(prompt);
          switch (outcome) {
            case AgentRendered(:final summary):
              stdout.writeln('+ $summary');
            case AgentSaid(:final text):
              stdout.writeln('agent: $text');
            case AgentFailed(:final error, :final attempts):
              stdout.writeln('x agent failed after $attempts rounds: $error');
          }
          stdout.writeln(console.snapshot());
        }
      case 'tree':
        stdout.writeln(console.treeDump());
      case 'help':
        stdout.writeln(_help);
      case 'quit':
      case 'exit':
        return false;
      default:
        stdout.writeln('unknown command: $cmd (try "help")');
    }
  } on Object catch (error) {
    stdout.writeln('error: $error');
  }
  return true;
}

/// The value following [flag] in [args], or null if absent (e.g. `--model x`).
String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i != -1 && i + 1 < args.length) ? args[i + 1] : null;
}

void _printOutcome(ConsentOutcome outcome) {
  switch (outcome) {
    case Applied(:final action, :final componentId, :final change):
      stdout.writeln('+ Applied $action on $componentId  $change');
    case Rejected():
      stdout.writeln('x Rejected: ${outcome.message}');
  }
}

const String _help = '''
genesis console — commands:
  load <file.json>        mount an updateComponents message (first time)
  apply <file.json>       reconcile a subsequent updateComponents message
  press <id> [amount]     fire a press action on a counter (amount defaults to 1)
  set <id> <key>=<value>  fire a set action (e.g. set c1 value=42)
  ask <prompt>            ask the agent to render/update the screen (swift-infer)
  tree                    dump the live branch tree
  help                    show this help
  quit                    exit''';

/// A sink that discards frame bytes — the REPL redraws full snapshots instead.
class _DiscardSink implements Sink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void close() {}
}
