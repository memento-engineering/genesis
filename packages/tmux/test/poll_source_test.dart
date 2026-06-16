import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:genesis_tmux/src/format.dart';
import 'package:test/test.dart';

/// One alive pane [pane] in window [win].
String _pane(String pane, String win) =>
    '$pane$fieldSep$win${fieldSep}100${fieldSep}1${fieldSep}0$fieldSep${fieldSep}bash';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('PollObservationSource', () {
    test('first poll primes a silent baseline (no events)', () async {
      final fake = FakeTmuxExecutor()
        ..handler = (a) => a.contains('list-panes')
            ? FakeTmuxExecutor.ok('${_pane('%0', '@0')}\n')
            : FakeTmuxExecutor.ok('hello\n');
      final client = TmuxClient(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        version: v3_6,
      );
      final source = PollObservationSource(client: client);
      final seen = <TmuxEvent>[];
      source.events.listen(seen.add);

      await source.poll();
      await _pump();
      expect(seen, isEmpty);
      await source.close();
    });

    test(
      'emits the appended suffix as PaneOutput on a grown capture',
      () async {
        var capture = 'hello';
        final fake = FakeTmuxExecutor()
          ..handler = (a) => a.contains('list-panes')
              ? FakeTmuxExecutor.ok('${_pane('%0', '@0')}\n')
              : FakeTmuxExecutor.ok(capture);
        final client = TmuxClient(
          executor: fake,
          socket: const TmuxSocket.named('s'),
          version: v3_6,
        );
        final source = PollObservationSource(client: client);
        final seen = <TmuxEvent>[];
        source.events.listen(seen.add);

        await source.poll(); // prime: lastCapture[%0] = 'hello'
        capture = 'hello world';
        await source.poll();
        await _pump();

        final out = seen.whereType<PaneOutput>().single;
        expect(out.paneId, '%0');
        expect(out.bytes, ' world'.codeUnits);
        await source.close();
      },
    );

    test('synthesizes WindowAdded / WindowClosed from the pane set', () async {
      var panes = '${_pane('%0', '@0')}\n';
      final fake = FakeTmuxExecutor()
        ..handler = (a) => a.contains('list-panes')
            ? FakeTmuxExecutor.ok(panes)
            : FakeTmuxExecutor.ok('x');
      final client = TmuxClient(
        executor: fake,
        socket: const TmuxSocket.named('s'),
        version: v3_6,
      );
      final source = PollObservationSource(client: client);
      final seen = <TmuxEvent>[];
      source.events.listen(seen.add);

      await source.poll(); // prime with @0
      panes = '${_pane('%0', '@0')}\n${_pane('%1', '@1')}\n';
      await source.poll(); // @1 appeared
      await _pump();
      expect(seen.whereType<WindowAdded>().single.windowId, '@1');

      seen.clear();
      panes = '${_pane('%0', '@0')}\n';
      await source.poll(); // @1 gone
      await _pump();
      expect(seen.whereType<WindowClosed>().single.windowId, '@1');
      await source.close();
    });
  });
}
