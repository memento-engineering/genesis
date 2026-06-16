@Tags(['integration'])
library;

import 'dart:io';

import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

bool _tmuxPresent() {
  try {
    return Process.runSync('tmux', ['-V']).exitCode == 0;
  } on Object {
    return false;
  }
}

/// Polls [cond] until true or [timeout] elapses.
Future<bool> _waitFor(
  Future<bool> Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

void main() {
  final present = _tmuxPresent();

  group(
    'integration (real tmux on an isolated -L socket)',
    () {
      // A per-run socket name keeps this off the developer's default tmux.
      final socket = TmuxSocket.named(
        'genesis-tmux-test-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      const exec = ProcessTmuxExecutor();
      late TmuxClient client;

      setUp(() {
        client = TmuxClient(executor: exec, socket: socket);
      });

      tearDownAll(() async {
        // Nuke only this isolated socket's server — never the default socket.
        await TmuxClient(executor: exec, socket: socket).killServer();
      });

      test('create / probe / send / capture / kill round-trip', () async {
        final pane = await client.newSession(name: 'verbs');
        expect(pane, startsWith('%'));
        expect(await client.hasSession('verbs'), isTrue);
        expect(
          (await client.listSessions()).map((s) => s.name),
          contains('verbs'),
        );
        expect(await client.listPanes(session: 'verbs'), isNotEmpty);
        expect(await client.panePid(pane), isNotNull);

        await client.sendKeys(pane, 'echo __GENESIS__');
        final showed = await _waitFor(
          () async => (await client.capturePane(
            pane,
            lines: 50,
          )).contains('__GENESIS__'),
        );
        expect(showed, isTrue, reason: 'the echoed output should render');

        await client.killSession('verbs');
        expect(await client.hasSession('verbs'), isFalse);
      });

      test('read-only control mode streams a pane %output frame', () async {
        final pane = await client.newSession(name: 'ctl');
        final source = ControlModeObservationSource(
          executor: exec,
          socket: socket,
          session: 'ctl',
        );
        final bytes = <int>[];
        source.paneOutput.listen((o) => bytes.addAll(o.bytes));
        await source.start();
        // Let the control client attach and size itself.
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // The blank line in the payload must survive the control-mode escaping.
        await client.sendKeys(pane, "printf 'x\\n\\n'");
        final got = await _waitFor(
          () async => String.fromCharCodes(bytes).contains('x'),
        );
        expect(got, isTrue, reason: 'control mode should stream pane output');

        await source.close();
        await client.killSession('ctl');
      });
    },
    skip: present ? false : 'tmux not installed',
  );
}
