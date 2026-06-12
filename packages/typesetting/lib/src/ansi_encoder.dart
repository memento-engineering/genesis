import 'dart:convert' show utf8;

import 'cell.dart';
import 'cell_grid.dart';

/// Encodes change lists into minimal ANSI escape sequences (ADR-0004
/// Decision 2).
///
/// Write-only output: cursor positioning (`ESC[row;colH`, 1-based) plus
/// 256-color SGR (`ESC[0;1;38;5;N;48;5;Mm`). Adjacent changed cells on the
/// same row share one cursor move (horizontal run batching); SGR is emitted
/// only when the style actually changes between emitted cells; a single
/// `ESC[0m` reset terminates the payload. No terminal queries, no raw mode,
/// no `dart:ffi` — safe under CI and pipes.
class AnsiEncoder {
  /// Creates an encoder. Stateless: every call is a self-contained payload.
  const AnsiEncoder();

  static const String _csi = '\x1b[';

  /// Encodes [changes] as a minimal ANSI payload; empty input encodes to the
  /// empty string (zero bytes for a no-change frame).
  String encode(List<CellChange> changes) {
    if (changes.isEmpty) return '';
    final sorted = List<CellChange>.of(changes)
      ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
    final sb = StringBuffer();
    int? fg, bg;
    bool? bold;
    var nextX = -1, nextY = -1;
    for (final ch in sorted) {
      if (ch.y != nextY || ch.x != nextX) {
        sb.write('$_csi${ch.y + 1};${ch.x + 1}H');
      }
      final c = ch.cell;
      if (c.fg != fg || c.bg != bg || c.bold != bold) {
        sb.write(_sgr(c));
        fg = c.fg;
        bg = c.bg;
        bold = c.bold;
      }
      sb.writeCharCode(c.rune);
      nextX = ch.x + 1;
      nextY = ch.y;
    }
    sb.write('${_csi}0m');
    return sb.toString();
  }

  /// UTF-8 bytes of [encode] (box-drawing runes are multi-byte).
  List<int> encodeBytes(List<CellChange> changes) =>
      utf8.encode(encode(changes));

  /// Byte cost of a naive full-screen redraw of [grid]'s front buffer,
  /// produced by the same encoder over every cell — the fair baseline that
  /// per-frame diffing is measured against.
  int fullRedrawBytes(CellGrid grid) {
    final all = <CellChange>[
      for (var y = 0; y < grid.height; y++)
        for (var x = 0; x < grid.width; x++)
          CellChange(x, y, grid.frontAt(x, y)),
    ];
    return encodeBytes(all).length;
  }

  String _sgr(Cell c) {
    final sb = StringBuffer('${_csi}0');
    if (c.bold) sb.write(';1');
    if (c.fg >= 0) sb.write(';38;5;${c.fg}');
    if (c.bg >= 0) sb.write(';48;5;${c.bg}');
    sb.write('m');
    return sb.toString();
  }
}
