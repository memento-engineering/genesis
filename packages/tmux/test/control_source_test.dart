import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

void main() {
  group('ControlModeObservationSource', () {
    test('sizes the control client, then pushes parsed events', () async {
      final fake = FakeTmuxExecutor();
      final source = ControlModeObservationSource(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        session: 'main',
      );
      await source.start();

      // Opens a read-only control connection on the right argv.
      expect(fake.lastCall, [
        '-u', '-L', 's', '-C', 'attach', '-t', '=main', //
      ]);
      // Sizes the client so output flows.
      expect(fake.lastControl.stdinWrites, ['refresh-client -C 80x24']);

      final evsF = source.events.take(2).toList();
      fake.lastControl
        ..add('%output %1 hi\\012')
        ..add('%window-add @4');
      final evs = await evsF;

      final out = evs[0] as PaneOutput;
      expect(out.paneId, '%1');
      expect(out.bytes, [104, 105, 10]);
      expect((evs[1] as WindowAdded).windowId, '@4');

      await source.close();
    });

    test('paneOutput is the filtered PaneOutput view of events', () async {
      final fake = FakeTmuxExecutor();
      final source = ControlModeObservationSource(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        session: 'main',
      );
      await source.start();

      final outF = source.paneOutput.first;
      fake.lastControl
        ..add('%window-add @4') // filtered out
        ..add('%output %2 x');
      expect((await outF).paneId, '%2');
      await source.close();
    });

    test('%exit surfaces an Exit and closes the stream', () async {
      final fake = FakeTmuxExecutor();
      final source = ControlModeObservationSource(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        session: 'main',
      );
      await source.start();

      final exitF = source.events.firstWhere((e) => e is Exit);
      final doneF = source.events.drain<void>(); // completes on stream close
      fake.lastControl.emitExit('server exited');

      expect(((await exitF) as Exit).reason, 'server exited');
      await doneF; // the connection ending closed the stream
    });

    test('emits subscription refresh-client -B frames when asked', () async {
      final fake = FakeTmuxExecutor();
      final source = ControlModeObservationSource(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        session: 'main',
        subscriptions: ['dead:%*:#{pane_dead}'],
      );
      await source.start();
      expect(fake.lastControl.stdinWrites, [
        'refresh-client -C 80x24',
        'refresh-client -B dead:%*:#{pane_dead}',
      ]);
      await source.close();
    });
  });

  group('subscriptions validation', () {
    ControlModeObservationSource build(
      FakeTmuxExecutor fake,
      List<String> subscriptions,
    ) => ControlModeObservationSource(
      executor: fake,
      socket: const TmuxSocket.named('s'),
      session: 'main',
      subscriptions: subscriptions,
    );

    Matcher rejects(String entry, String code) => throwsA(
      isA<ArgumentError>()
          .having((e) => e.name, 'name', 'subscriptions')
          .having((e) => e.invalidValue, 'invalidValue', entry)
          .having((e) => '${e.message}', 'message', contains(code)),
    );

    void rejectsCharacter(String description, String char, String code) {
      test('rejects an entry containing $description ($code)', () {
        final fake = FakeTmuxExecutor();
        final entry = 'dead:%*:$char#{pane_dead}';
        expect(() => build(fake, [entry]), rejects(entry, code));
        expect(fake.calls, isEmpty);
        expect(fake.controls, isEmpty);
      });
    }

    rejectsCharacter('a newline', '\n', 'U+000A');
    rejectsCharacter('a carriage return', '\r', 'U+000D');
    rejectsCharacter('a semicolon', ';', 'U+003B');
    rejectsCharacter('a single quote', "'", 'U+0027');
    rejectsCharacter('NUL', '\u0000', 'U+0000');
    rejectsCharacter('DEL', '\u007F', 'U+007F');
    rejectsCharacter('a tab', '\t', 'U+0009');

    test('rejects an unsafe entry after a safe one', () {
      final fake = FakeTmuxExecutor();
      expect(
        () => build(fake, ['ok:%*:#{pane_dead}', 'bad;kill-server']),
        rejects('bad;kill-server', 'U+003B'),
      );
      expect(fake.calls, isEmpty);
      expect(fake.controls, isEmpty);
    });

    test('a later change to the caller list changes nothing written', () async {
      final fake = FakeTmuxExecutor();
      final subscriptions = <String>['dead:%*:#{pane_dead}'];
      final source = build(fake, subscriptions);
      subscriptions.add('x;kill-server');
      await source.start();
      expect(fake.lastControl.stdinWrites, [
        'refresh-client -C 80x24',
        'refresh-client -B dead:%*:#{pane_dead}',
      ]);
      await source.close();
    });
  });
}
