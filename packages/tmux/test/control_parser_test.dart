import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

void main() {
  late ControlModeParser p;
  setUp(() => p = ControlModeParser());

  group('%output decoding', () {
    test('octal-escaped bytes -> exact PaneOutput bytes', () {
      final evs = p.feed('%output %1 hello\\012');
      final out = evs.single as PaneOutput;
      expect(out.paneId, '%1');
      expect(out.bytes, [104, 101, 108, 108, 111, 10]);
    });

    test('a literal backslash arrives as \\134', () {
      final out = p.feed('%output %2 a\\134b').single as PaneOutput;
      expect(out.bytes, [97, 0x5C, 98]);
      expect(out.paneId, '%2');
    });

    test('a blank line survives (escaped CRLF)', () {
      final out = p.feed('%output %1 \\015\\012').single as PaneOutput;
      expect(out.bytes, [13, 10]);
    });

    test('output data with interior spaces is preserved', () {
      final out = p.feed('%output %1 a b c').single as PaneOutput;
      expect(out.bytes, 'a b c'.codeUnits);
    });
  });

  group('command-reply framing', () {
    test('a %begin..%end block emits nothing', () {
      expect(p.feed('%begin 1700000000 7 1'), isEmpty);
      expect(p.inBlock, isTrue);
      expect(p.feed('some reply payload'), isEmpty);
      expect(p.feed('%end 1700000000 7 1'), isEmpty);
      expect(p.inBlock, isFalse);
    });

    test('an %error block also closes the block', () {
      p.feed('%begin 1 2 0');
      expect(p.feed('%error 1 2 0'), isEmpty);
      expect(p.inBlock, isFalse);
    });

    test('a notification after a reply block is not mis-attributed', () {
      p
        ..feed('%begin 1 2 0')
        ..feed('reply')
        ..feed('%end 1 2 0');
      expect(p.feed('%window-add @5').single, isA<WindowAdded>());
    });

    test('tolerates extra/opaque %begin trailing fields', () {
      expect(p.feed('%begin 1 2 0 extra fields'), isEmpty);
      expect(p.inBlock, isTrue);
    });
  });

  group('lifecycle notifications', () {
    test('%window-add / %window-close', () {
      expect((p.feed('%window-add @3').single as WindowAdded).windowId, '@3');
      expect(
        (p.feed('%window-close @3').single as WindowClosed).windowId,
        '@3',
      );
    });

    test('%window-renamed keeps a name with spaces', () {
      final e =
          p.feed('%window-renamed @0 my new name').single as WindowRenamed;
      expect(e.windowId, '@0');
      expect(e.name, 'my new name');
    });

    test('%session-changed / %sessions-changed', () {
      final e = p.feed('%session-changed \$2 work').single as SessionChanged;
      expect(e.sessionId, '\$2');
      expect(e.name, 'work');
      expect(p.feed('%sessions-changed').single, isA<SessionsChanged>());
    });

    test('%pane-mode-changed', () {
      expect(
        (p.feed('%pane-mode-changed %1').single as PaneModeChanged).paneId,
        '%1',
      );
    });

    test('%exit with and without a reason', () {
      expect((p.feed('%exit').single as Exit).reason, isNull);
      expect(
        (p.feed('%exit server exited').single as Exit).reason,
        'server exited',
      );
    });

    test('unhandled notifications are parsed and ignored', () {
      expect(p.feed('%client-detached client'), isEmpty);
      expect(p.feed('%layout-change @0 abc'), isEmpty);
      expect(p.feed('%unlinked-window-add @9'), isEmpty);
    });
  });
}
