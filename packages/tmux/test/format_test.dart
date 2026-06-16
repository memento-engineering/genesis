import 'package:genesis_tmux/src/format.dart';
import 'package:test/test.dart';

void main() {
  group('octalDecode', () {
    test('decodes an escaped control byte (\\012 -> 0x0A)', () {
      expect(octalDecode('hello\\012'), [104, 101, 108, 108, 111, 10]);
    });

    test('decodes an escaped CRLF to bytes (blank line intact)', () {
      // A blank output line arrives as its escaped CRLF and must survive.
      expect(octalDecode('\\015\\012'), [13, 10]);
      expect(octalDecode('x\\015\\012'), [120, 13, 10]);
    });

    test('decodes a literal backslash (arrives escaped as \\134)', () {
      expect(octalDecode('a\\134b'), [97, 0x5C, 98]);
    });

    test('passes through a raw high byte losslessly (latin1)', () {
      // A byte >= 0x80 may arrive unescaped; one code unit -> one byte.
      final value = String.fromCharCodes([0xE9]); // é in latin1
      expect(octalDecode(value), [0xE9]);
    });

    test('leaves a trailing lone backslash literal', () {
      expect(octalDecode('a\\'), [97, 0x5C]);
    });
  });

  group('field splitting', () {
    test('splits on the field separator, preserving interior content', () {
      final fields = splitFields('a${fieldSep}b c${fieldSep}d:e');
      expect(fields, ['a', 'b c', 'd:e']);
    });

    test('strips a trailing CR but no interior content', () {
      expect(splitFields('a${fieldSep}b\r'), ['a', 'b']);
    });

    test('parseRecords drops blank lines, one record per line', () {
      final out = 'a${fieldSep}1\nb${fieldSep}2\n';
      expect(parseRecords(out), [
        ['a', '1'],
        ['b', '2'],
      ]);
    });

    test('formatSpec joins tokens with the field separator', () {
      expect(formatSpec(['#{a}', '#{b}']), '#{a}$fieldSep#{b}');
    });
  });
}
