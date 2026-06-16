/// Spawn a detached tmux session, send a command, read it back, and observe
/// lifecycle events — all on an isolated `-L` socket that is torn down on exit,
/// so it never touches your default tmux. Self-skips when tmux is absent.
///
///   dart run example/genesis_tmux_example.dart
library;

import 'dart:io';

import 'package:genesis_tmux/genesis_tmux.dart';

Future<void> main() async {
  if (!_tmuxPresent()) {
    stdout.writeln('tmux not found on PATH — skipping the example.');
    return;
  }

  final client = TmuxClient(
    executor: const ProcessTmuxExecutor(),
    socket: TmuxSocket.named('genesis-tmux-example-$pid'),
  );

  // Observe lifecycle events (Model A: poll-backed) while we work.
  final source = PollObservationSource(client: client);
  source.events.listen((event) => stdout.writeln('  event: $event'));
  await source.start();

  try {
    final pane = await client.newSession(name: 'demo');
    stdout.writeln('created session "demo" -> pane $pane');

    await client.sendKeys(pane, 'echo hello from genesis_tmux');
    await _waitFor(
      () async => (await client.capturePane(pane, lines: 50)).contains('hello'),
    );

    stdout.writeln('--- captured pane ---');
    stdout.writeln(await client.capturePane(pane, lines: 5));

    stdout.writeln(
      'sessions: ${(await client.listSessions()).map((s) => s.name).toList()}',
    );
    stdout.writeln('pane alive: ${!await client.paneDead(pane)}');
  } finally {
    await source.close();
    await client.killServer();
    stdout.writeln('done — isolated server killed.');
  }
}

bool _tmuxPresent() {
  try {
    return Process.runSync('tmux', ['-V']).exitCode == 0;
  } on Object {
    return false;
  }
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
