import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:test/test.dart';

void main() {
  group('isValidSessionName', () {
    test('accepts the allowlist (letters, digits, _ , -)', () {
      expect(isValidSessionName('agent_42-x'), isTrue);
    });

    test('rejects dots, colons, slashes, target sigils, and empty', () {
      for (final bad in ['a.b', 'a:b', 'a/b', '=a', '%1', r'$0', '@0', '']) {
        expect(isValidSessionName(bad), isFalse, reason: bad);
      }
    });
  });

  group('sanitizeBeadId', () {
    test('maps / . : to --', () {
      expect(sanitizeBeadId('genesis/4m1.2:3'), 'genesis--4m1--2--3');
    });

    test('sanitized ids round-trip into valid session names', () {
      expect(isValidSessionName(sanitizeBeadId('a/b.c')), isTrue);
    });
  });

  group('TmuxSocket', () {
    test('named socket emits -L before the subcommand', () {
      expect(const TmuxSocket.named('genesis').args, ['-L', 'genesis']);
    });

    test('path socket emits -S', () {
      expect(const TmuxSocket.path('/tmp/s.sock').args, ['-S', '/tmp/s.sock']);
    });
  });
}
