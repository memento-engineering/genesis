/// The spike-2 property suite as real tests (ADR-0004 Decision 2): diff
/// correctness, diff minimality, idempotence, and emission economy — all
/// deterministic (constant RNG seed).
library;

import 'dart:math';

import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

void main() {
  group('double-buffer diff', () {
    test('correctness: replaying the change list onto the old front buffer '
        'reproduces the back buffer (8 randomized rounds, seed 42)', () {
      const rounds = 8;
      final rng = Random(42);
      final grid = CellGrid(40, 12);
      grid.drawBox(0, 0, 40, 12, title: 'typesetting', fg: 6);
      grid.swap(); // establish a non-trivial frame 0

      for (var round = 0; round < rounds; round++) {
        final before = grid.frontSnapshot();
        _randomMutations(grid, rng, round);
        final changes = grid.swap();

        final replay = List<Cell>.of(before);
        for (final ch in changes) {
          replay[ch.y * grid.width + ch.x] = ch.cell;
        }
        expect(
          replay,
          grid.frontSnapshot(),
          reason:
              'round $round: replay of the change list must reproduce '
              'the promoted back buffer exactly',
        );
      }
    });

    test('minimality: change count == ground-truth differing cells; '
        'no-op rewrites never appear (8 randomized rounds, seed 42)', () {
      const rounds = 8;
      final rng = Random(42);
      final grid = CellGrid(40, 12);
      grid.drawBox(0, 0, 40, 12, title: 'typesetting', fg: 6);
      grid.swap();

      for (var round = 0; round < rounds; round++) {
        _randomMutations(grid, rng, round);

        // Ground truth BEFORE swap: cells where back actually differs from
        // front (no-op rewrites are equal and must not count).
        var expected = 0;
        for (var y = 0; y < grid.height; y++) {
          for (var x = 0; x < grid.width; x++) {
            if (grid.backAt(x, y) != grid.frontAt(x, y)) expected++;
          }
        }

        final changes = grid.swap();
        expect(
          changes.length,
          expected,
          reason:
              'round $round: the diff must contain exactly the '
              'differing cells',
        );
      }
    });

    test('idempotence: swap with no draws yields 0 changes', () {
      final grid = CellGrid(20, 6);
      grid.drawBox(1, 1, 18, 4, title: 'idem', fg: 2);
      grid.swap();
      expect(grid.swap(), isEmpty);
    });

    test('explicit no-op rewrite yields 0 changes', () {
      final grid = CellGrid(20, 6);
      grid.putText(2, 2, 'stable', fg: 3);
      grid.swap();
      grid.set(2, 2, grid.backAt(2, 2)); // rewrite the existing value
      expect(grid.swap(), isEmpty);
    });
  });

  group('emission economy', () {
    test('k changed cells emit far fewer bytes than a full redraw '
        '(same-encoder baseline)', () {
      const enc = AnsiEncoder();
      final grid = CellGrid(80, 25); // N = 2000

      // Frame 1: initial scene (large k — diffing buys little, by design).
      grid.drawBox(2, 1, 30, 8, title: 'alpha', fg: 6);
      grid.drawBox(40, 3, 24, 10, title: 'beta', fg: 3);
      grid.putText(4, 20, 'status: nominal', fg: 2, bold: true);
      var changes = grid.swap();
      expect(
        enc.encodeBytes(changes).length,
        lessThan(enc.fullRedrawBytes(grid)),
        reason: 'even the initial frame must beat the full redraw',
      );

      // Frames 2..4: small mutations — diff must beat the redraw by >= 10x.
      for (var frame = 2; frame <= 4; frame++) {
        grid.putText(4, 20, 'status: frame $frame', fg: 5, bold: frame.isEven);
        grid.set(60 + frame, 22, const Cell(0x2588, fg: 1)); // block █
        changes = grid.swap();
        final emitted = enc.encodeBytes(changes).length;
        final full = enc.fullRedrawBytes(grid);
        expect(
          changes.length,
          lessThan(32),
          reason: 'frame $frame: k must actually be small',
        );
        expect(
          emitted,
          lessThan(full ~/ 10),
          reason:
              'frame $frame: $emitted bytes for ${changes.length} '
              'cells must be well under full redraw ($full bytes)',
        );
      }
    });
  });

  group('AnsiEncoder contract', () {
    const enc = AnsiEncoder();

    test('empty change list encodes to zero bytes', () {
      expect(enc.encode(const []), isEmpty);
      expect(enc.encodeBytes(const []), isEmpty);
    });

    test('single cell: 1-based cursor address, then a trailing reset', () {
      final payload = enc.encode(const [
        CellChange(4, 2, Cell(0x41, fg: 2, bold: true)),
      ]);
      expect(payload, startsWith('\x1b[3;5H'));
      expect(payload, contains('\x1b[0;1;38;5;2m'));
      expect(payload, endsWith('A\x1b[0m'));
    });

    test('horizontal run batching: adjacent same-row cells share one move', () {
      final payload = enc.encode(const [
        CellChange(5, 1, Cell(0x61)),
        CellChange(6, 1, Cell(0x62)),
        CellChange(7, 1, Cell(0x63)),
      ]);
      expect(
        'H'.allMatches(payload).length,
        1,
        reason: 'one cursor move for the whole run',
      );
      expect(payload, contains('abc'));
    });

    test('SGR emitted only on style transitions', () {
      final payload = enc.encode(const [
        CellChange(0, 0, Cell(0x61, fg: 2)),
        CellChange(1, 0, Cell(0x62, fg: 2)), // same style: no new SGR
        CellChange(2, 0, Cell(0x63, fg: 3)), // transition: new SGR
      ]);
      // 1 leading SGR + 1 transition + 1 trailing reset.
      expect('m'.allMatches(payload).length, 3);
    });
  });
}

/// Deterministic random draw ops, including no-op rewrites (case 3) that
/// must never appear in the diff.
void _randomMutations(CellGrid g, Random rng, int round) {
  final nOps = 3 + rng.nextInt(6);
  for (var i = 0; i < nOps; i++) {
    switch (rng.nextInt(4)) {
      case 0: // single styled cell
        g.set(
          rng.nextInt(g.width),
          rng.nextInt(g.height),
          Cell(
            0x41 + rng.nextInt(26),
            fg: rng.nextInt(16),
            bg: rng.nextBool() ? rng.nextInt(16) : -1,
            bold: rng.nextBool(),
          ),
        );
      case 1: // text run (may clip at the right edge)
        g.putText(
          rng.nextInt(g.width),
          rng.nextInt(g.height),
          'r$round-op$i',
          fg: rng.nextInt(256),
          bold: rng.nextBool(),
        );
      case 2: // box (may clip)
        g.drawBox(
          rng.nextInt(g.width - 6),
          rng.nextInt(g.height - 3),
          6 + rng.nextInt(10),
          3 + rng.nextInt(4),
          title: 'b$i',
          fg: rng.nextInt(16),
        );
      case 3: // no-op rewrite: must NOT show up in the diff
        final x = rng.nextInt(g.width), y = rng.nextInt(g.height);
        g.set(x, y, g.backAt(x, y));
      default:
        throw StateError('unreachable');
    }
  }
}
