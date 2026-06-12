import 'dart:async';
import 'dart:collection';

import 'package:genesis_tree/genesis_tree.dart';

import 'ansi_encoder.dart';
import 'cell_grid.dart';
import 'frame_record.dart';
import 'rect.dart';
import 'render_branch.dart';

/// The root render seed (register A23): a fixed [width] x [height] cell
/// surface emitting ANSI bytes to [sink], stacking its [children]'s render
/// branches top-to-bottom full-width (layout v1 flow).
///
/// Mounting a Stage is the whole entry point — the binding folds into the
/// tree:
///
/// ```dart
/// final owner = TreeOwner();
/// owner.mountRoot(Stage(width: 80, height: 24, sink: stdout, children: [
///   // Watch / Stateless / perception composition over Box / Text ...
/// ]));
/// // frame 0 is painted; from here, painting just happens.
/// ```
///
/// Write-only: the stage emits diff payloads and nothing else — no
/// clear-screen, no cursor parking, no terminal queries. Screen setup and
/// teardown are the embedder's choice (ADR-0004 Decision 1).
class Stage extends RenderSeed {
  /// Creates the root surface configuration.
  const Stage({
    required this.width,
    required this.height,
    required this.sink,
    this.children = const [],
    this.onFrame,
    super.key,
  });

  /// Surface width in columns. Fixed for the stage's lifetime (resize is
  /// ADR-0004 backlog).
  final int width;

  /// Surface height in rows.
  final int height;

  /// Receives the UTF-8 ANSI payload of every non-empty frame.
  final Sink<List<int>> sink;

  /// The child configurations — composition seeds and/or render seeds; the
  /// stage flows whatever render branches they resolve to.
  final List<Seed> children;

  /// Per-frame observer, called after each [FrameRecord] is recorded.
  final void Function(FrameRecord frame)? onFrame;

  @override
  StageBranch createBranch() => StageBranch(this);
}

/// The root render branch — the RenderView analog (register A23) and the
/// scheduling glue's owner. At mount it creates its [StageBinding], claims
/// `TreeOwner.onNeedsFlush`, builds its subtree, and paints frame 0
/// synchronously; after that, every dirty edge schedules one microtask frame
/// pass.
///
/// Per-frame instrumentation ([frames], [flushCount]) and the surface
/// ([grid], [encoder]) are reachable from here for tests and ops.
class StageBranch extends RenderBranch {
  /// Creates the branch for [seed].
  StageBranch(Stage super.seed);

  Stage get _stage => seed as Stage;

  StageBinding? _ownedBinding;
  List<Branch> _children = const [];

  StageBinding get _owned {
    final binding = _ownedBinding;
    if (binding == null) {
      throw StateError('StageBranch used before mount().');
    }
    return binding;
  }

  /// The double-buffered surface. Exposed so tests and ops can read the
  /// front buffer and compute full-redraw baselines.
  CellGrid get grid => _owned.grid;

  /// The encoder producing the emitted payloads (and the full-redraw
  /// baseline via [AnsiEncoder.fullRedrawBytes]).
  AnsiEncoder get encoder => _owned.encoder;

  /// Every frame recorded so far, frame 0 first (unmodifiable view).
  List<FrameRecord> get frames => _owned.frames;

  /// Number of flush passes run (excludes the initial frame-0 paint).
  int get flushCount => _owned.flushCount;

  /// Claims the binding role instead of attaching to a render parent: the
  /// stage IS the render root. Asserts it is not nested inside another
  /// render scope and that this owner's flush callback is unclaimed.
  @override
  void attachRenderParent() {
    assert(
      dependOnInheritedSeedOfExactType<RenderParentLink>() == null,
      'Stage must be the render root; it cannot be mounted inside another '
      'render branch.',
    );
    final owner = this.owner!;
    assert(
      owner.onNeedsFlush == null,
      'TreeOwner.onNeedsFlush is already claimed; a Stage must be the only '
      'flush driver on its owner.',
    );
    final binding = StageBinding._(
      stage: this,
      owner: owner,
      width: _stage.width,
      height: _stage.height,
      sink: _stage.sink,
      onFrame: _stage.onFrame,
    );
    _ownedBinding = binding;
    attachBinding(binding);
    owner.onNeedsFlush = binding._requestFrame;
  }

  @override
  void mount(Branch? parent, Object? slot) {
    // Base mount attaches the binding (attachRenderParent override above)
    // and runs performRebuild, mounting and adopting the whole subtree.
    super.mount(parent, slot);
    // Frame 0: lay out, paint, and emit the full scene synchronously, so
    // mountRoot returns with the surface populated.
    _owned._renderInitialFrame();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, [
      for (final child in _stage.children) renderScopeFor(child),
    ]);
    super.performRebuild();
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  int get flowHeight => _stage.height;

  /// Layout v1 flow: stacks render children top-to-bottom, full-width, each
  /// taking the rows its [RenderBranch.flowHeight] reports. Children past
  /// the bottom edge are clipped by the grid.
  @override
  void performLayout() {
    var y = rect.top;
    for (final child in renderChildren) {
      child.layout(Rect.fromLTWH(rect.left, y, rect.width, child.flowHeight));
      y += child.flowHeight;
    }
  }

  /// The stage's own cells are the background: blank.
  @override
  void paint(CellGrid grid) => clearRect(grid);

  @override
  void unmount() {
    _ownedBinding?._detach();
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}

/// The thin scheduling-and-pipeline glue the stage branch owns (register
/// A23): the BuildOwner-edge-to-PipelineOwner wiring, folded into the tree.
///
/// `TreeOwner.onNeedsFlush` (the dirty set's empty -> non-empty edge) ->
/// one scheduled microtask -> `owner.flush()` -> the verbatim drained list
/// -> flow relayout if anything changed shape -> repaint exactly the dirty
/// render branches' rects -> `CellGrid.swap()` -> minimal ANSI to the sink,
/// recorded as a [FrameRecord]. Events arriving before the pass coalesce.
///
/// The paint pass is the `PipelineOwner.flushPaint` analog — it drains the
/// dirty set in depth order and paints each still-attached branch's subtree
/// (Flutter: `final List<RenderObject> dirtyNodes = _nodesNeedingPaint;`
/// then paint each node still owned and dirty). Depth order runs parents
/// first, so container blanking never erases freshly painted child content;
/// overlapping repaints are deduped by the double buffer, not by skipping.
///
/// Constructed only by [StageBranch] at mount; consumers reach it through
/// the stage branch's instrumentation getters.
class StageBinding {
  StageBinding._({
    required StageBranch stage,
    required TreeOwner owner,
    required int width,
    required int height,
    required Sink<List<int>> sink,
    void Function(FrameRecord frame)? onFrame,
  }) : _stage = stage,
       _owner = owner,
       grid = CellGrid(width, height),
       _sink = sink,
       _onFrame = onFrame;

  final StageBranch _stage;
  final TreeOwner _owner;
  final Sink<List<int>> _sink;
  final void Function(FrameRecord frame)? _onFrame;

  /// The double-buffered surface.
  final CellGrid grid;

  /// The stateless encoder for payloads and full-redraw baselines.
  final AnsiEncoder encoder = const AnsiEncoder();

  /// Dirty render branches awaiting paint, drained in depth order (parents
  /// before children) — the `_nodesNeedingPaint` analog.
  final SplayTreeSet<RenderBranch> _needsPaint = SplayTreeSet((a, b) {
    final byDepth = a.depth.compareTo(b.depth);
    return byDepth != 0 ? byDepth : a.branchId.compareTo(b.branchId);
  });

  final List<FrameRecord> _frames = [];

  bool _needsLayout = true;
  bool _rectChanged = false;
  bool _passScheduled = false;
  bool _inPass = false;
  bool _detached = false;
  int _flushCount = 0;

  /// Every frame recorded so far, frame 0 first (unmodifiable view).
  List<FrameRecord> get frames => List.unmodifiable(_frames);

  /// Number of flush passes run (excludes the initial frame-0 paint).
  int get flushCount => _flushCount;

  /// Adds [branch] to the dirty-paint set and requests a frame pass. Called
  /// by [RenderBranch.markNeedsPaint].
  void scheduleRepaint(RenderBranch branch) {
    _needsPaint.add(branch);
    _requestFrame();
  }

  /// Flags the stage-rooted flow relayout and requests a frame pass. Called
  /// by [RenderBranch.markNeedsLayout].
  void scheduleRelayout() {
    _needsLayout = true;
    _requestFrame();
  }

  /// Notes that a layout pass moved or resized some branch's rect, so
  /// vacated cells must be cleared (the stage repaints). Called by
  /// [RenderBranch.layout].
  void noteRectChanged() {
    _rectChanged = true;
  }

  void _requestFrame() {
    if (_passScheduled || _inPass || _detached) return;
    _passScheduled = true;
    scheduleMicrotask(_framePass);
  }

  void _framePass() {
    _passScheduled = false;
    if (_detached) return;
    _inPass = true;
    try {
      final rebuilt = _owner.flush();
      if (rebuilt.isEmpty && _needsPaint.isEmpty && !_needsLayout) {
        // A spurious wakeup (e.g. the pass scheduled during mount, already
        // consumed by frame 0): nothing to do, record nothing.
        return;
      }
      _flushCount++;
      _renderFrame(rebuilt);
    } finally {
      _inPass = false;
    }
  }

  void _renderInitialFrame() {
    _inPass = true;
    try {
      _renderFrame(const []);
    } finally {
      _inPass = false;
    }
  }

  void _renderFrame(List<Branch> rebuilt) {
    // Layout (flow v1): recompute rects from the stage down; if any rect
    // moved, the stage repaints so vacated cells are cleared — the double
    // buffer keeps emission minimal regardless.
    if (_needsLayout) {
      _needsLayout = false;
      _rectChanged = false;
      _stage.layout(Rect.fromLTWH(0, 0, grid.width, grid.height));
      if (_rectChanged) scheduleRepaint(_stage);
    }
    // Paint (flushPaint analog): drain depth-ordered, parents first.
    final dirty = List<RenderBranch>.of(_needsPaint);
    _needsPaint.clear();
    final repainted = <Rect>{};
    for (final branch in dirty) {
      if (!branch.mounted || !identical(branch.binding, this)) continue;
      branch.paintSubtree(grid);
      repainted.add(branch.rect);
    }
    // Swap, encode, emit, record.
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
    _onFrame?.call(frame);
  }

  void _detach() {
    if (_detached) return;
    _detached = true;
    _owner.onNeedsFlush = null;
    _needsPaint.clear();
  }
}
