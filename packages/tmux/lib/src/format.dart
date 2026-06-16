/// FORMAT-string plumbing and the control-mode octal decoder.
///
/// tmux `-F` output is parsed with explicit, collision-proof delimiters — a
/// U+241E field separator and U+001F unit separator — never tab or colon,
/// which appear inside pane titles, commands, and paths and silently corrupt a
/// split. [octalDecode] reverses control mode's `\ooo` escaping of `%output`
/// payloads.
library;

/// Field separator woven into `-F` format strings and split back out. U+241E
/// (SYMBOL FOR RECORD SEPARATOR) never occurs in tmux format values.
const String fieldSep = '␞';

/// Secondary (unit) separator for nesting a list inside one field. U+001F.
const String unitSep = '';

/// Builds a `-F` format string from [tokens] (each a `#{…}` spec) joined by
/// [fieldSep], so the output of one item is one delimiter-separated line.
String formatSpec(List<String> tokens) => tokens.join(fieldSep);

/// Splits one `-F` output line into its fields on [fieldSep]. A trailing
/// carriage return (CRLF terminals) is stripped; interior content is never
/// trimmed.
List<String> splitFields(String line) {
  final clean = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
  return clean.split(fieldSep);
}

/// Parses multi-line `-F` [stdout] into one record (a field list) per
/// non-empty line. Blank trailing lines (tmux ends output with a newline) are
/// dropped; genuinely empty interior records do not occur because every record
/// carries at least one format token.
List<List<String>> parseRecords(String stdout) {
  final records = <List<String>>[];
  for (final raw in stdout.split('\n')) {
    if (raw.isEmpty) continue;
    records.add(splitFields(raw));
  }
  return records;
}

/// Decodes a control-mode `%output` value, reversing tmux's octal escaping.
///
/// tmux escapes every byte below 0x20 and the backslash itself as `\ooo`
/// (three octal digits — a literal backslash arrives as `\134`). Bytes ≥ 0x80
/// may pass through raw, so [value] must be a *latin1* string (one code unit
/// per byte) for a lossless round-trip. The result is the exact original
/// bytes; the caller decides UTF-8/VT interpretation.
List<int> octalDecode(String value) {
  final bytes = <int>[];
  var i = 0;
  while (i < value.length) {
    final c = value.codeUnitAt(i);
    if (c == 0x5C /* \ */ && i + 3 < value.length) {
      final d1 = value.codeUnitAt(i + 1);
      final d2 = value.codeUnitAt(i + 2);
      final d3 = value.codeUnitAt(i + 3);
      if (_isOctal(d1) && _isOctal(d2) && _isOctal(d3)) {
        bytes.add(((d1 - 0x30) << 6) | ((d2 - 0x30) << 3) | (d3 - 0x30));
        i += 4;
        continue;
      }
    }
    bytes.add(c & 0xFF);
    i += 1;
  }
  return bytes;
}

bool _isOctal(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x37;
