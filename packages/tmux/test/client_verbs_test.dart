import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:genesis_tmux/src/format.dart';
import 'package:test/test.dart';

/// Builds a client on a named socket; [version] skips the `tmux -V` probe.
TmuxClient _client(FakeTmuxExecutor fake, {TmuxVersion? version}) => TmuxClient(
  executor: fake,
  socket: const TmuxSocket.named('s'),
  version: version ?? v3_6,
);

List<String> _callWith(FakeTmuxExecutor fake, String verb) =>
    fake.calls.firstWhere((c) => c.contains(verb));

/// One delimited `-F` output record.
String _rec(List<String> fields) => fields.join(fieldSep);

void main() {
  group('argv builder', () {
    test('prepends -u and the socket before the subcommand', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) => a.contains('has-session')
            ? FakeTmuxExecutor.fail("can't find session")
            : null;
      await _client(fake).hasSession('agent');
      expect(fake.lastCall, ['-u', '-L', 's', 'has-session', '-t', '=agent']);
    });

    test('the client timeout cap is passed through to the executor', () async {
      Duration? seen;
      final exec = _RecordingTimeoutExecutor((t) => seen = t);
      await TmuxClient(
        executor: exec,
        socket: const TmuxSocket.named('s'),
        version: v3_6,
        timeout: const Duration(seconds: 5),
      ).capturePane('%0');
      expect(seen, const Duration(seconds: 5));
    });
  });

  group('hasSession', () {
    test('exact-match -t =name, true on success', () async {
      final fake = FakeTmuxExecutor(); // default ok('')
      expect(await _client(fake).hasSession('agent'), isTrue);
      expect(fake.lastCall, ['-u', '-L', 's', 'has-session', '-t', '=agent']);
    });

    test('false on "can\'t find session", not a throw', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (_) => FakeTmuxExecutor.fail("can't find session: agent");
      expect(await _client(fake).hasSession('agent'), isFalse);
    });

    test('false when no server is running', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (_) => FakeTmuxExecutor.fail('no server running on …');
      expect(await _client(fake).hasSession('agent'), isFalse);
    });
  });

  group('newSession', () {
    test('atomic pane-id learn, hygiene, and the returned pane id', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) {
          if (a.contains('has-session')) {
            return FakeTmuxExecutor.fail("can't find session");
          }
          if (a.contains('new-session')) return FakeTmuxExecutor.ok('%3\n');
          return null;
        };
      final pane = await _client(
        fake,
      ).newSession(name: 'agent', workdir: '/work');
      expect(pane, '%3');
      expect(_callWith(fake, 'new-session'), [
        '-u', '-L', 's', 'new-session', '-d', '-s', 'agent', //
        '-c', '/work', '-P', '-F', '#{pane_id}',
      ]);
      // Post-create hygiene ran.
      expect(_callWith(fake, 'exit-empty'), [
        '-u', '-L', 's', 'set-option', '-g', 'exit-empty', 'off', //
      ]);
      expect(_callWith(fake, 'window-size'), [
        '-u', '-L', 's', 'set-option', '-wt', '=agent', //
        'window-size', 'latest',
      ]);
    });

    test('inline -e env on tmux >= 3.2', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) => a.contains('has-session')
            ? FakeTmuxExecutor.fail("can't find session")
            : (a.contains('new-session') ? FakeTmuxExecutor.ok('%1') : null);
      await _client(
        fake,
        version: v3_2,
      ).newSession(name: 'agent', env: {'FOO': 'bar'});
      expect(
        _callWith(fake, 'new-session'),
        containsAllInOrder(['-e', 'FOO=bar']),
      );
    });

    test('refuses -e env on tmux < 3.2 (guard)', () async {
      final fake = FakeTmuxExecutor();
      expect(
        () => _client(
          fake,
          version: const TmuxVersion(3, 1),
        ).newSession(name: 'agent', env: {'FOO': 'bar'}),
        throwsA(isA<TmuxGuardException>()),
      );
    });

    test('refuses an invalid session name before tmux', () async {
      final fake = FakeTmuxExecutor();
      expect(
        () => _client(fake).newSession(name: 'a.b'),
        throwsA(isA<TmuxGuardException>()),
      );
      expect(fake.calls, isEmpty);
    });

    test('clobber guard: refuses to create over a live session', () async {
      final fake = FakeTmuxExecutor(); // has-session returns ok -> exists
      expect(
        () => _client(fake).newSession(name: 'agent'),
        throwsA(isA<TmuxDuplicateSession>()),
      );
    });
  });

  group('killSession', () {
    test('exact -t =name', () async {
      final fake = FakeTmuxExecutor();
      await _client(fake).killSession('agent');
      expect(fake.lastCall, ['-u', '-L', 's', 'kill-session', '-t', '=agent']);
    });

    test('idempotent: a missing session is a no-op', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (_) => FakeTmuxExecutor.fail("can't find session");
      await _client(fake).killSession('agent'); // does not throw
    });

    test('refuses the -a kill-all shorthand', () async {
      final fake = FakeTmuxExecutor();
      expect(
        () => _client(fake).killSession('-a'),
        throwsA(isA<TmuxGuardException>()),
      );
      expect(fake.calls, isEmpty);
    });
  });

  group('listSessions / listPanes', () {
    test('parses delimited session records', () async {
      final out =
          '${_rec(['\$0', 'main', '1', '2'])}\n'
          '${_rec(['\$1', 'work', '0', '1'])}\n';
      final fake = FakeTmuxExecutor()
        ..handler = (a) =>
            a.contains('list-sessions') ? FakeTmuxExecutor.ok(out) : null;
      final sessions = await _client(fake).listSessions();
      expect(sessions, hasLength(2));
      expect(sessions[0].id, '\$0');
      expect(sessions[0].name, 'main');
      expect(sessions[0].attached, isTrue);
      expect(sessions[0].windows, 2);
      expect(sessions[1].attached, isFalse);
    });

    test('empty list when no server is running', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (_) => FakeTmuxExecutor.fail('no server running on …');
      expect(await _client(fake).listSessions(), isEmpty);
    });

    test('list-panes uses -s and parses an empty dead-status field', () async {
      final out = '${_rec(['%0', '@0', '1234', '1', '0', '', 'bash'])}\n';
      final fake = FakeTmuxExecutor()
        ..handler = (a) =>
            a.contains('list-panes') ? FakeTmuxExecutor.ok(out) : null;
      final panes = await _client(fake).listPanes(session: 'main');
      expect(_callWith(fake, 'list-panes').sublist(3, 7), [
        'list-panes',
        '-s',
        '-t',
        '=main',
      ]);
      final p = panes.single;
      expect(p.id, '%0');
      expect(p.windowId, '@0');
      expect(p.pid, 1234);
      expect(p.active, isTrue);
      expect(p.dead, isFalse);
      expect(p.deadStatus, isNull);
      expect(p.currentCommand, 'bash');
    });
  });

  group('capturePane / probes', () {
    test('bounded tail with -S -N; strips one trailing newline', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) =>
            a.contains('capture-pane') ? FakeTmuxExecutor.ok('l1\nl2\n') : null;
      final out = await _client(fake).capturePane('%0', lines: 50);
      expect(out, 'l1\nl2');
      expect(fake.lastCall, [
        '-u', '-L', 's', 'capture-pane', '-p', '-t', '%0', '-S', '-50', //
      ]);
    });

    test('probes read #{...} via display-message -p', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) {
          final fmt = a.last;
          if (fmt == '#{pane_pid}') return FakeTmuxExecutor.ok('4321\n');
          if (fmt == '#{pane_dead}') return FakeTmuxExecutor.ok('1\n');
          if (fmt == '#{pane_in_mode}') return FakeTmuxExecutor.ok('0\n');
          return FakeTmuxExecutor.ok('\n');
        };
      final c = _client(fake);
      expect(await c.panePid('%0'), 4321);
      expect(await c.paneDead('%0'), isTrue);
      expect(await c.paneInMode('%0'), isFalse);
    });
  });

  group('sendKeys', () {
    FakeTmuxExecutor notInMode() =>
        FakeTmuxExecutor()
          ..handler = (a) =>
              a.last == '#{pane_in_mode}' ? FakeTmuxExecutor.ok('0') : null;

    test('literal -l as one argv element, Enter sent separately', () async {
      final fake = notInMode();
      await _client(fake).sendKeys('%1', 'hello world; rm -rf');
      final literal = _callWith(fake, '-l');
      expect(literal, [
        '-u',
        '-L',
        's',
        'send-keys',
        '-t',
        '%1',
        '-l',
        'hello world; rm -rf', //
      ]);
      // Enter is its own send-keys call (no trailing bare ';').
      expect(fake.calls.last, [
        '-u',
        '-L',
        's',
        'send-keys',
        '-t',
        '%1',
        'Enter',
      ]);
    });

    test('payloads over 4096 bytes go through a paste buffer', () async {
      final fake = notInMode();
      final big = 'x' * 5000;
      await _client(fake).sendKeys('%1', big, enter: false);
      expect(_callWith(fake, 'set-buffer'), [
        '-u', '-L', 's', 'set-buffer', '-b', 'genesis-0', big, //
      ]);
      expect(_callWith(fake, 'paste-buffer'), [
        '-u', '-L', 's', 'paste-buffer', '-p', '-d', '-b', 'genesis-0', //
        '-t', '%1',
      ]);
    });

    test('serializes concurrent sends to one pane in order', () async {
      final fake = notInMode();
      final c = _client(fake);
      final a = c.sendKeys('%1', 'A', enter: false);
      final b = c.sendKeys('%1', 'B', enter: false);
      await Future.wait([a, b]);
      final literals = fake.calls
          .where((c) => c.contains('-l'))
          .map((c) => c.last)
          .toList();
      expect(literals, ['A', 'B']);
    });
  });
}

/// An executor that reports the timeout passed to [runOnce].
class _RecordingTimeoutExecutor implements TmuxExecutor {
  _RecordingTimeoutExecutor(this.onTimeout);
  final void Function(Duration?) onTimeout;

  @override
  Future<TmuxResult> runOnce(List<String> argv, {Duration? timeout}) async {
    onTimeout(timeout);
    return TmuxResult(argv: argv, exitCode: 0, stdout: '', stderr: '');
  }

  @override
  TmuxControlConn openControl(List<String> argv) => throw UnimplementedError();
}
