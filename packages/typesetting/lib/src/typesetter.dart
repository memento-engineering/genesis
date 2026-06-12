import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import 'ansi_encoder.dart';
import 'cell.dart';
import 'cell_grid.dart';
import 'paint_delegate.dart';

/// Everything recorded about one emit pass — the per-frame instrumentation
/// surface (regions repainted, cells changed, bytes emitted) for tests and
/// ops.
class FrameRecord {
  /// Creates a record; all collections are stored unmodifiable.
  FrameRecord({
    required this.index,
    required List<Branch> rebuilt,
    required Set<Region> repainted,
    required List<CellChange> changes,
    required this.bytes,
  }) : rebuilt = List.unmodifiable(rebuilt),
       repainted = Set.unmodifiable(repainted),
       changes = List.unmodifiable(changes);

  /// 0 = the initial full paint at mount; 1.. = flush passes.
  final int index;

  /// The verbatim [TreeOwner.flush] return for this pass (empty for frame
  /// 0, which is a paint, not a flush) — the real drained dirty set, no side
  /// channel.
  final List<Branch> rebuilt;

  /// The regions repainted into the back buffer this pass, mapped from
  /// [rebuilt] by [PaintDelegate.regionFor].
  final Set<Region> repainted;

  /// Minimal cell diff from [CellGrid.swap].
  final List<CellChange> changes;

  /// UTF-8 ANSI bytes emitted for this frame (empty when nothing changed).
  final List<int> bytes;

  /// Number of cells that actually changed on screen this frame.
  int get cellsChanged => changes.length;

  /// Number of ANSI bytes emitted this frame.
  int get bytesEmitted => bytes.length;

  @override
  String toString() =>
      'FrameRecord(#$index, rebuilt=${rebuilt.length}, '
      'repainted=${repainted.length}, cells=$cellsChanged, '
      'bytes=$bytesEmitted)';
}

/// The live loop (ADR-0004 Decision 2, spike 4 productionized): wires a
/// [TreeOwner] to a [CellGrid] and a byte sink through a consumer-supplied
/// [PaintDelegate].
///
/// `onNeedsFlush` (which fires on the dirty set's empty -> non-empty edge)
/// schedules one microtask pass: `owner.flush()` -> the drained list of
/// rebuilt branches -> regions via [PaintDelegate.regionFor] (the REAL
/// drained dirty set — spike 4's builder-driven `RepaintNotifier` fake is
/// gone, per ADR-0001 Decision 5 / ADR-0004 Decision 4) -> repaint only
/// those regions into the back buffer -> [CellGrid.swap] -> minimal ANSI to
/// [sink]. Events arriving before the pass runs coalesce into it naturally.
///
/// Write-only: the typesetter emits diff payloads and nothing else — no
/// clear-screen, no cursor parking, no terminal queries. Screen setup and
/// teardown are the embedder's choice (ADR-0004 Decision 1).
class Typesetter {
  /// Creates a typesetter over a fresh [width] x [height] grid, emitting
  /// ANSI bytes to [sink]. Call [mount] to plant the tree and paint frame 0.
  Typesetter({
    required this.delegate,
    required int width,
    required int height,
    required Sink<List<int>> sink,
    this.onFrame,
  }) : grid = CellGrid(width, height),
       _sink = sink;

  /// The consumer's paint seam: region assignment + painting semantics.
  final PaintDelegate delegate;

  /// The double-buffered surface. Exposed so tests and ops can read the
  /// front buffer and compute full-redraw baselines.
  final CellGrid grid;

  /// The encoder producing the emitted payloads (and the full-redraw
  /// baseline via [AnsiEncoder.fullRedrawBytes]).
  final AnsiEncoder encoder = const AnsiEncoder();

  /// Per-frame observer, called after each [FrameRecord] is recorded.
  final void Function(FrameRecord frame)? onFrame;

  final Sink<List<int>> _sink;
  final TreeOwner _owner = TreeOwner();
  final List<FrameRecord> _frames = [];

  Branch? _root;
  List<Region> _regions = const [];
  int _flushCount = 0;
  bool _passScheduled = false;
  bool _disposed = false;

  /// The mounted root branch. Throws [StateError] before [mount].
  Branch get root {
    final r = _root;
    if (r == null) {
      throw StateError('root accessed before mount()');
    }
    return r;
  }

  /// The canonical regions returned by [PaintDelegate.assignRegions] at
  /// mount (unmodifiable).
  List<Region> get regions => _regions;

  /// Every frame emitted so far, frame 0 first (unmodifiable view).
  List<FrameRecord> get frames => List.unmodifiable(_frames);

  /// Number of flush passes run (excludes the initial frame-0 paint).
  int get flushCount => _flushCount;

  /// Mounts [seed] as the root of a fresh tree, lets the delegate assign
  /// regions, paints the full scene as frame 0, and starts listening for
  /// flushes. Returns the root branch.
  Branch mount(Seed seed) {
    if (_root != null) {
      throw StateError('mount() called twice');
    }
    if (_disposed) {
      throw StateError('mount() called after dispose()');
    }
    _owner.onNeedsFlush = _scheduleFlush;
    final mounted = _owner.mountRoot(seed);
    _root = mounted;
    _regions = List.unmodifiable(delegate.assignRegions(mounted));
    for (final region in _regions) {
      delegate.paint(grid, region);
    }
    _emit(rebuilt: const [], repainted: {..._regions});
    return mounted;
  }

  /// Unmounts the tree (cancelling subscriptions via branch unmount) and
  /// stops emitting. Idempotent; a pending scheduled pass becomes a no-op.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner.dispose();
  }

  void _scheduleFlush() {
    if (_passScheduled || _disposed) return;
    _passScheduled = true;
    scheduleMicrotask(_flushPass);
  }

  void _flushPass() {
    _passScheduled = false;
    if (_disposed) return;
    final rebuilt = _owner.flush();
    _flushCount++;
    final repainted = <Region>{};
    for (final branch in rebuilt) {
      final region = delegate.regionFor(branch);
      if (region == null) continue;
      assert(
        _regions.contains(region),
        'regionFor returned a Region not assigned by assignRegions: $region',
      );
      repainted.add(region);
    }
    for (final region in repainted) {
      delegate.paint(grid, region);
    }
    _emit(rebuilt: rebuilt, repainted: repainted);
  }

  void _emit({required List<Branch> rebuilt, required Set<Region> repainted}) {
    final changes = grid.swap();
    final bytes = encoder.encodeBytes(changes);
    final frame = FrameRecord(
      index: _frames.length,
      rebuilt: rebuilt,
      repainted: repainted,
      changes: changes,
      bytes: bytes,
    );
    _frames.add(frame);
    if (bytes.isNotEmpty) _sink.add(bytes);
    onFrame?.call(frame);
  }
}
