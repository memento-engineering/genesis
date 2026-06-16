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
}
