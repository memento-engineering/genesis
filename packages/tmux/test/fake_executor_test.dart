import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

/// Whether [future] has completed after the pending microtasks have run.
Future<bool> _completed(Future<void> future) async {
  var done = false;
  () async {
    await future;
    done = true;
  }().ignore();
  await Future<void>.delayed(Duration.zero);
  return done;
}

void main() {
  group('FakeControlConn', () {
    test('closing stdin is counted and completes done by default', () async {
      final fake = FakeControlConn();
      expect(fake.stdinClosed, isFalse);
      expect(await _completed(fake.conn.done), isFalse);

      fake.conn.stdin.close();

      expect(fake.stdinCloses, 1);
      expect(fake.stdinClosed, isTrue);
      expect(fake.kills, 0);
      expect(await _completed(fake.conn.done), isTrue);
    });

    test('a child that ignores stdin closing exits only when killed', () async {
      final fake = FakeControlConn(exitsOnStdinClose: false);

      fake.conn.stdin.close();
      expect(fake.stdinCloses, 1);
      expect(await _completed(fake.conn.done), isFalse);

      fake.conn.kill();
      expect(fake.kills, 1);
      expect(await _completed(fake.conn.done), isTrue);
    });

    test(
      'a kill after done already completed is harmless and counted',
      () async {
        final fake = FakeControlConn();
        fake.conn.stdin.close();
        await fake.conn.done;

        expect(fake.conn.kill, returnsNormally);
        expect(fake.kills, 1);
        fake.kill();
        expect(fake.kills, 2);
        expect(await _completed(fake.conn.done), isTrue);
      },
    );
  });

  group('FakeTmuxExecutor', () {
    test('hands its stdin-close behaviour to every connection it opens', () {
      final cooperative = FakeTmuxExecutor()..openControl(['-C']);
      expect(cooperative.lastControl.exitsOnStdinClose, isTrue);

      final stubborn = FakeTmuxExecutor(controlExitsOnStdinClose: false)
        ..openControl(['-C'])
        ..openControl(['-C']);
      expect(
        stubborn.controls.map((c) => c.exitsOnStdinClose),
        everyElement(isFalse),
      );
    });
  });
}
