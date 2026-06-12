import 'package:genesis_tree/genesis_tree.dart';

import 'cell.dart';
import 'rect.dart';

/// Everything recorded about one frame pass — the per-frame instrumentation
/// surface (rebuilt branches, repainted rects, cells changed, bytes emitted)
/// for tests and ops, reachable from the stage branch (`StageBranch.frames`).
class FrameRecord {
  /// Creates a record; all collections are stored unmodifiable.
  FrameRecord({
    required this.index,
    required List<Branch> rebuilt,
    required Set<Rect> repainted,
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

  /// The rects of the dirty render branches repainted into the back buffer
  /// this pass.
  final Set<Rect> repainted;

  /// Minimal cell diff from `CellGrid.swap`.
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
