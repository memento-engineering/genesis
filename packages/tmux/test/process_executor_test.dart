@TestOn('vm')
library;

import 'dart:io';

import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

/// Exercises [ProcessTmuxExecutor]'s control-connection lifecycle against
/// `sh` and a missing binary, so it needs no tmux.
void main() {
  group('ProcessTmuxExecutor.openControl', () {
    const missing = ProcessTmuxExecutor(
      executable: '/nonexistent/genesis-tmux-missing',
    );

    test('a child that fails to start completes done, even when nothing '
        'reads its lines and input was written', () async {
      final conn = missing.openControl(['-C'])
        ..stdin.add('refresh-client -C 80x24')
        ..stdin.close();
      await conn.done.timeout(const Duration(seconds: 5));
      // A kill for a child that never existed is harmless.
      conn.kill();
    });

    test('a source over a child that fails to start closes without '
        'hanging', () async {
      final source = ControlModeObservationSource(
        executor: missing,
        socket: const TmuxSocket.named('genesis-missing'),
        session: 'ctl',
      );
      var eventsDone = false;
      source.events.listen(null, onDone: () => eventsDone = true);
      await source.start();
      await source.close().timeout(const Duration(seconds: 5));
      expect(eventsDone, isTrue);
    });

    test('every line the child printed before exiting is delivered before '
        'done', () async {
      const count = 5000;
      const shell = ProcessTmuxExecutor(executable: 'sh');
      final conn = shell.openControl([
        '-c',
        'i=0; while [ \$i -lt $count ]; do echo line\$i; i=\$((i+1)); done',
      ]);
      final seen = <String>[];
      conn.lines.listen(seen.add);
      await conn.done.timeout(const Duration(seconds: 10));
      expect(seen, hasLength(count));
      expect(seen.last, 'line${count - 1}');
    }, skip: Platform.isWindows ? 'needs a POSIX sh' : false);

    test('closing stdin delivers EOF, so a child reading to EOF exits and '
        'done completes without a kill', () async {
      const shell = ProcessTmuxExecutor(executable: 'sh');
      final conn = shell.openControl(['-c', 'cat']);
      final seen = <String>[];
      conn.lines.listen(seen.add);
      conn.stdin.add('hello');
      conn.stdin.close();
      await conn.done.timeout(const Duration(seconds: 5));
      expect(seen, ['hello']);
    }, skip: Platform.isWindows ? 'needs a POSIX sh' : false);
  });
}
