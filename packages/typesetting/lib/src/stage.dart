import 'dart:async';
import 'dart:collection';

import 'package:genesis_tree/genesis_tree.dart';

import 'ansi_encoder.dart';
import 'cell_grid.dart';
import 'frame_record.dart';
import 'rect.dart';
import 'render_element.dart';

/// The root render component: a fixed [width] x [height] cell
/// surface emitting ANSI bytes to [sink], stacking its [children]'s render
/// elements top-to-bottom full-width (layout v1 flow).
///
/// Mounting a Stage is the whole entry point — the binding folds into the
/// tree:
///
/// ```dart
/// final owner = BuildOwner();
/// owner.mountRoot(Stage(width: 80, height: 24, sink: stdout, children: [
///   // Watch / Stateless / perception composition over Box / Text ...
/// ]));
/// // frame 0 is painted; from here, painting just happens.
/// ```
///
/// Write-only: the stage emits diff payloads and nothing else — no
/// clear-screen, no cursor parking, no terminal queries. Screen setup and
/// teardown are the embedder's choice.
class Stage extends RenderComponent {
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
  /// backlog).
  final int width;

  /// Surface height in rows.
  final int height;

  /// Receives the UTF-8 ANSI payload of every non-empty frame.
  final Sink<List<int>> sink;

  /// The child configurations — composition seeds and/or render seeds; the
  /// stage flows whatever render elements they resolve to.
  final List<Component> children;

  /// Per-frame observer, called after each [FrameRecord] is recorded.
  final void Function(FrameRecord frame)? onFrame;

  @override
  StageElement createElement() => StageElement(this);
}

/// The root render element — the RenderView analog and the
/// scheduling glue's owner. At mount it creates its [StageBinding], claims
/// `BuildOwner.onNeedsFlush`, builds its subtree, and paints frame 0
/// synchronously; after that, every dirty edge schedules one microtask frame
/// pass.
///
/// Per-frame instrumentation ([frames], [flushCount]) and the surface
/// ([grid], [encoder]) are reachable from here for tests and ops.
class StageElement extends RenderElement {
  /// Creates the element for [component].
  StageElement(Stage super.component);

  Stage get _stage => component as Stage;

  StageBinding? _ownedBinding;
  List<Element> _children = const [];

  StageBinding get _owned {
    final binding = _ownedBinding;
    if (binding == null) {
      throw StateError('StageElement used before mount().');
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
      dependOnInheritedValueOfExactType<RenderParentLink>() == null,
      'Stage must be the render root; it cannot be mounted inside another '
      'render element.',
    );
    final owner = this.owner!;
    assert(
      owner.onNeedsFlush == null,
      'BuildOwner.onNeedsFlush is already claimed; a Stage must be the only '
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
    owner.onNeedsFlush = binding._onOwnerNeedsFlush;
  }

  @override
  void mount(Element? parent, Object? slot) {
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
  void visitChildren(void Function(Element child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  int get flowHeight => _stage.height;

  /// Layout v1 flow: stacks render children top-to-bottom, full-width, each
  /// taking the rows its [RenderElement.flowHeight] reports. Children past
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

/// The thin scheduling-and-pipeline glue the stage element owns: the
/// BuildOwner-edge-to-PipelineOwner wiring, folded into the tree.
///
/// `BuildOwner.onNeedsFlush` (the dirty set's empty -> non-empty edge) ->
/// one scheduled microtask -> `owner.flush()` -> the verbatim drained list
/// -> flow relayout if anything changed shape -> repaint exactly the dirty
/// render elements' rects -> `CellGrid.swap()` -> minimal ANSI to the sink,
/// recorded as a [FrameRecord]. Events arriving before the pass coalesce.
///
/// The paint pass is the `PipelineOwner.flushPaint` analog — it drains the
/// dirty set in depth order and paints each still-attached element's subtree
/// (Flutter: `final List<RenderObject> dirtyNodes = _nodesNeedingPaint;`
/// then paint each node still owned and dirty). Depth order runs parents
/// first, so container blanking never erases freshly painted child content.
/// A dirty element that a render ancestor's subtree paint already reached in
/// this pass is not painted again — the ancestor's paint covered it — so each
/// render element paints at most once per frame, and a covered element still
/// counts as repainted in the frame's record.
///
/// Requests raised during a pass: a pass runs public callbacks — component
/// builds during `owner.flush()`, layout, paint, the sink's `add`, and
/// `onFrame` — and any of them may request a repaint, a relayout or a
/// rebuild. Such a request is never dropped. If the running pass still
/// consumes the work (a build's repaint lands before the paint step), that
/// pass serves it and no extra frame is spent. If the pass completes and work
/// is left over, exactly one follow-up pass is scheduled by microtask; every
/// request raised during the pass coalesces into it. Frame 0, painted
/// synchronously at mount, follows the same rule.
///
/// A pass that throws: the error propagates unchanged (out of the microtask,
/// or out of mount for frame 0) and no follow-up is scheduled, so a
/// deterministic fault cannot loop. The scheduler stays live — the next
/// request schedules a pass normally — and work the throwing pass had not yet
/// reached stays queued for it: elements not yet painted remain dirty and an
/// unfinished relayout remains flagged. An element whose own paint threw —
/// painting on its own or inside an ancestor's subtree paint — counts as
/// attempted and is not retried. Nothing is retried automatically.
///
/// Once the stage unmounts, the binding ignores every request.
///
/// Constructed only by [StageElement] at mount; consumers reach it through
/// the stage element's instrumentation getters.
class StageBinding {
  StageBinding._({
    required StageElement stage,
    required BuildOwner owner,
    required int width,
    required int height,
    required Sink<List<int>> sink,
    void Function(FrameRecord frame)? onFrame,
  }) : _stage = stage,
       _owner = owner,
       grid = CellGrid(width, height),
       _sink = sink,
       _onFrame = onFrame;

  final StageElement _stage;
  final BuildOwner _owner;
  final Sink<List<int>> _sink;
  final void Function(FrameRecord frame)? _onFrame;

  /// The double-buffered surface.
  final CellGrid grid;

  /// The stateless encoder for payloads and full-redraw baselines.
  final AnsiEncoder encoder = const AnsiEncoder();

  /// Dirty render elements awaiting paint, drained in depth order (parents
  /// before children) — the `_nodesNeedingPaint` analog.
  final SplayTreeSet<RenderElement> _needsPaint = SplayTreeSet((a, b) {
    final byDepth = a.depth.compareTo(b.depth);
    return byDepth != 0 ? byDepth : a.elementId.compareTo(b.elementId);
  });

  final List<FrameRecord> _frames = [];

  bool _needsLayout = true;
  bool _rectChanged = false;
  bool _passScheduled = false;
  bool _inPass = false;
  bool _detached = false;

  /// A frame request arrived while a pass was running.
  bool _requestedInPass = false;

  /// The owner reported new dirty work after the last `flush()` returned.
  bool _ownerNeedsFlush = false;

  /// Bumped by a throwing pass; a queued pass from an older generation is
  /// void and does nothing when its microtask runs.
  int _passGeneration = 0;
  int _flushCount = 0;

  /// Every frame recorded so far, frame 0 first (unmodifiable view).
  List<FrameRecord> get frames => List.unmodifiable(_frames);

  /// Number of flush passes run (excludes the initial frame-0 paint).
  int get flushCount => _flushCount;

  /// Adds [element] to the dirty-paint set and requests a frame pass. Called
  /// by [RenderElement.markNeedsPaint].
  /// Ignored once the stage has unmounted.
  void scheduleRepaint(RenderElement element) {
    if (_detached) return;
    _needsPaint.add(element);
    _requestFrame();
  }

  /// Flags the stage-rooted flow relayout and requests a frame pass. Called
  /// by [RenderElement.markNeedsLayout]. Ignored once the stage has
  /// unmounted.
  void scheduleRelayout() {
    if (_detached) return;
    _needsLayout = true;
    _requestFrame();
  }

  /// Notes that a layout pass moved or resized some element's rect, so
  /// vacated cells must be cleared (the stage repaints). Called by
  /// [RenderElement.layout].
  void noteRectChanged() {
    _rectChanged = true;
  }

  /// Elements whose paint began in the running paint step; null outside it.
  Set<RenderElement>? _paintedInPass;

  /// The running paint step's repainted rects; null outside it.
  Set<Rect>? _repaintedInPass;

  /// Notes that [element]'s own paint is about to run. Called by
  /// [RenderElement.paintSubtree] before each element paints.
  ///
  /// During this binding's paint step, a dirty [element] leaves the
  /// dirty-paint set here — before it paints, so a repaint requested during
  /// or after its paint stays queued — and its rect counts as repainted this
  /// frame. Outside the paint step this does nothing.
  void notePainting(RenderElement element) {
    final painted = _paintedInPass;
    if (painted == null || !identical(element.binding, this)) return;
    painted.add(element);
    if (_needsPaint.remove(element)) _repaintedInPass!.add(element.rect);
  }

  /// The owner's dirty-set edge: notes owner work, then requests a frame.
  void _onOwnerNeedsFlush() {
    if (_detached) return;
    _ownerNeedsFlush = true;
    _requestFrame();
  }

  void _requestFrame() {
    if (_detached) return;
    if (_inPass) {
      // Served by the running pass if it still consumes the work, else by
      // the one follow-up scheduled when the pass completes.
      _requestedInPass = true;
      return;
    }
    if (_passScheduled) return;
    _passScheduled = true;
    final generation = _passGeneration;
    scheduleMicrotask(() {
      // A throwing pass voids every pass queued before it ended: running one
      // would retry the faulted work automatically.
      if (generation != _passGeneration) return;
      _framePass();
    });
  }

  /// Whether dirty work remains that no pass has served yet.
  bool get _hasOutstandingWork =>
      _ownerNeedsFlush || _needsPaint.isNotEmpty || _needsLayout;

  /// Ends a pass: clears the in-pass state and, only when the pass
  /// [completed] normally, schedules the one follow-up an in-pass request
  /// earned for work the pass left over. A throwing pass schedules nothing.
  void _endPass({required bool completed}) {
    _inPass = false;
    final requested = _requestedInPass;
    _requestedInPass = false;
    if (!completed) {
      // Void any pass already queued (frame 0's throw leaves the one its
      // mount-time builds scheduled) and leave the scheduler idle, so the
      // next request schedules a pass normally.
      _passGeneration++;
      _passScheduled = false;
      return;
    }
    if (requested && _hasOutstandingWork) _requestFrame();
  }

  void _framePass() {
    _passScheduled = false;
    if (_detached) return;
    _inPass = true;
    _requestedInPass = false;
    var completed = false;
    try {
      final rebuilt = _owner.flush();
      // Owner work raised during the flush was rebuilt by that flush.
      _ownerNeedsFlush = false;
      if (rebuilt.isEmpty && _needsPaint.isEmpty && !_needsLayout) {
        // A spurious wakeup (e.g. the pass scheduled during mount, already
        // consumed by frame 0): nothing to do, record nothing.
        completed = true;
        return;
      }
      _flushCount++;
      _renderFrame(rebuilt);
      completed = true;
    } finally {
      _endPass(completed: completed);
    }
  }

  void _renderInitialFrame() {
    _inPass = true;
    _requestedInPass = false;
    var completed = false;
    try {
      _renderFrame(const []);
      completed = true;
    } finally {
      _endPass(completed: completed);
    }
  }

  void _renderFrame(List<Element> rebuilt) {
    // Layout (flow v1): recompute rects from the stage down; if any rect
    // moved, the stage repaints so vacated cells are cleared — the double
    // buffer keeps emission minimal regardless.
    if (_needsLayout) {
      _needsLayout = false;
      _rectChanged = false;
      try {
        _stage.layout(Rect.fromLTWH(0, 0, grid.width, grid.height));
      } catch (_) {
        // The relayout did not finish: keep it flagged for the next pass.
        _needsLayout = true;
        rethrow;
      }
      if (_rectChanged) scheduleRepaint(_stage);
    }
    // Paint (flushPaint analog): drain depth-ordered, parents first. Each
    // element leaves the set just before its own paint runs — whether the
    // loop paints it or an ancestor's subtree paint reaches it first
    // (notePainting) — so a throw leaves the elements not yet reached queued
    // for the next pass, while the element that threw counts as attempted.
    // An element an ancestor's paint already covered this pass is skipped:
    // each element paints at most once per frame, and a repaint requested
    // after its paint began stays queued for the follow-up pass.
    final dirty = List<RenderElement>.of(_needsPaint);
    final painted = Set<RenderElement>.identity();
    final repainted = <Rect>{};
    _paintedInPass = painted;
    _repaintedInPass = repainted;
    try {
      for (final element in dirty) {
        if (painted.contains(element)) continue;
        if (!_needsPaint.remove(element)) continue;
        if (!element.mounted || !identical(element.binding, this)) continue;
        element.paintSubtree(grid);
        painted.add(element);
        repainted.add(element.rect);
      }
    } finally {
      _paintedInPass = null;
      _repaintedInPass = null;
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
    _requestedInPass = false;
    _ownerNeedsFlush = false;
  }
}

/// Legacy name for [StageElement].
@Deprecated('Use StageElement instead.')
typedef StageBranch = StageElement;
