import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

void main() {
  group('TmuxVersion.parse', () {
    test('parses a plain "tmux X.Y"', () {
      final v = TmuxVersion.parse('tmux 3.4');
      expect(v.major, 3);
      expect(v.minor, 4);
      expect(v.isMaster, isFalse);
    });

    test('strips a trailing letter (3.6b -> 3.6)', () {
      final v = TmuxVersion.parse('tmux 3.6b');
      expect(v.major, 3);
      expect(v.minor, 6);
    });

    test('parses a bare token without the "tmux " prefix', () {
      expect(TmuxVersion.parse('3.2a'), TmuxVersion.parse('tmux 3.2'));
    });

    test('parses a "-master"/word suffix down to its numeric core', () {
      final v = TmuxVersion.parse('tmux 2.4-master');
      expect(v.major, 2);
      expect(v.minor, 4);
    });

    test('treats an unnumbered master as the newest version', () {
      final v = TmuxVersion.parse('tmux master');
      expect(v.isMaster, isTrue);
      expect(v.hasMin(v3_6), isTrue);
      expect(v.hasGt(TmuxVersion.parse('tmux 9.9')), isTrue);
    });

    test('records the raw output for explainability', () {
      expect(TmuxVersion.parse('tmux 3.6b').raw, 'tmux 3.6b');
    });
  });

  group('comparison + gates', () {
    test('orders by (major, minor)', () {
      expect(TmuxVersion.parse('3.2').hasLt(TmuxVersion.parse('3.4')), isTrue);
      expect(TmuxVersion.parse('3.4').hasGt(TmuxVersion.parse('3.2')), isTrue);
      expect(TmuxVersion.parse('4.0').hasGt(TmuxVersion.parse('3.9')), isTrue);
    });

    test('KNOWN QUIRK: 3.2a == 3.2 (letter strip is lossy)', () {
      expect(TmuxVersion.parse('3.2a'), TmuxVersion.parse('3.2'));
      expect(TmuxVersion.parse('3.2a').hasMin(v3_2), isTrue);
    });

    test('feature gates fire at their floors', () {
      final v31 = TmuxVersion.parse('3.1');
      final v32 = TmuxVersion.parse('3.2');
      final v34 = TmuxVersion.parse('3.4');
      expect(v31.supportsNewSessionEnv, isFalse);
      expect(v32.supportsNewSessionEnv, isTrue);
      expect(v32.supportsControlSubscriptions, isTrue);
      expect(v32.supportsSendKeysK, isFalse);
      expect(v34.supportsSendKeysK, isTrue);
      expect(v34.supportsCapturePaneTrim, isTrue);
      expect(v34.supportsDestroyUnattachedKeep, isTrue);
    });
  });
}
