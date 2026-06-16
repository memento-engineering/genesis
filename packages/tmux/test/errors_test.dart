import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

TmuxResult _fail(String stderr, {int exitCode = 1}) => TmuxResult(
  argv: const ['has-session'],
  exitCode: exitCode,
  stdout: '',
  stderr: stderr,
);

void main() {
  group('wrapTmuxError classification', () {
    test('"no server running" -> TmuxNoServer', () {
      expect(
        _fail('no server running on /tmp/tmux-501/genesis').let(wrapTmuxError),
        isA<TmuxNoServer>(),
      );
    });

    test('"can\'t find session" -> TmuxNotFound(session)', () {
      final e = wrapTmuxError(_fail("can't find session: agent"));
      expect(e, isA<TmuxNotFound>());
      expect((e as TmuxNotFound).object, TmuxObject.session);
      expect(e.target, 'agent');
    });

    test('"can\'t find pane" -> TmuxNotFound(pane)', () {
      final e = wrapTmuxError(_fail("can't find pane: %9"));
      expect((e as TmuxNotFound).object, TmuxObject.pane);
    });

    test('"can\'t find window" -> TmuxNotFound(window)', () {
      final e = wrapTmuxError(_fail("can't find window: @9"));
      expect((e as TmuxNotFound).object, TmuxObject.window);
    });

    test('"duplicate session" -> TmuxDuplicateSession', () {
      final e = wrapTmuxError(_fail('duplicate session: agent'));
      expect(e, isA<TmuxDuplicateSession>());
      expect((e as TmuxDuplicateSession).name, 'agent');
    });

    test('unmatched stderr -> TmuxCommandFailed (the catch-all)', () {
      final e = wrapTmuxError(_fail('some other failure', exitCode: 2));
      expect(e, isA<TmuxCommandFailed>());
      expect((e as TmuxCommandFailed).exitCode, 2);
    });

    test('every member carries the argv and a non-empty message', () {
      final e = wrapTmuxError(_fail("can't find session: x"));
      expect(e.argv, ['has-session']);
      expect(e.message, isNotEmpty);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
