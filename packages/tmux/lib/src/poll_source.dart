/// Model A — the default observation source: poll the verbs and diff.
///
/// Lifecycle events come from diffing the window set across `list-panes`
/// snapshots; live output comes from diffing bounded `capture-pane` tails.
/// This is the proven low-dependency approach: no parser, no connection
/// lifecycle, trivially fakeable. Output is necessarily approximate (a rendered
/// grid, not a byte
/// stream — there is no "settled" signal), so prefer Model B for low-latency,
/// byte-exact output when tmux ≥ 3.2.
library;

import 'dart:async';
import 'dart:convert';

import 'client.dart';
import 'events.dart';
import 'observation.dart';

/// Polls a [TmuxClient] on a fixed tick and emits synthesized [TmuxEvent]s.
///
/// [poll] runs one diff pass and is public so tests (and manual drivers) can
/// step it deterministically without a timer.
class PollObservationSource implements ObservationSource {
  /// Observes [client]; restricts to [session] when given. Each pass captures
  /// the last [captureLines] of each pane; [interval] is the auto-poll tick.
  PollObservationSource({
    required TmuxClient client,
    String? session,
    int captureLines = 200,
    Duration interval = const Duration(seconds: 1),
  }) : _client = client,
       _session = session,
       _captureLines = captureLines,
       _interval = interval;

  final TmuxClient _client;
  final String? _session;
  final int _captureLines;
  final Duration _interval;

  final StreamController<TmuxEvent> _events =
      StreamController<TmuxEvent>.broadcast();

  Timer? _timer;
  bool _busy = false;
  bool _primed = false;
  Set<String> _windows = const {};
  final Map<String, String> _lastCapture = {};

  @override
  Stream<TmuxEvent> get events => _events.stream;

  @override
  Stream<PaneOutput> get paneOutput =>
      _events.stream.where((e) => e is PaneOutput).cast<PaneOutput>();

  @override
  Future<void> start() async {
    await poll(); // prime a silent baseline
    _timer = Timer.periodic(_interval, (_) {
      if (!_busy) unawaited(poll());
    });
  }

  /// Runs one poll pass: diffs the window set and each pane's captured tail
  /// against the last snapshot, emitting the differences. The first pass
  /// primes the baseline and emits nothing.
  Future<void> poll() async {
    if (_busy) return; // never overlap a pass
    _busy = true;
    try {
      final panes = await _client.listPanes(session: _session);
      final windows = {for (final p in panes) p.windowId};

      if (_primed) {
        for (final w in windows.difference(_windows)) {
          _emit(WindowAdded(w));
        }
        for (final w in _windows.difference(windows)) {
          _emit(WindowClosed(w));
        }
      }
      _windows = windows;

      final live = <String>{};
      for (final p in panes) {
        live.add(p.id);
        if (p.dead) continue;
        final cap = await _client.capturePane(p.id, lines: _captureLines);
        final prev = _lastCapture[p.id];
        _lastCapture[p.id] = cap;
        if (prev != null && cap != prev) {
          // Grew in place → emit the appended suffix; otherwise the redraw.
          final delta = cap.startsWith(prev) ? cap.substring(prev.length) : cap;
          if (delta.isNotEmpty) _emit(PaneOutput(p.id, utf8.encode(delta)));
        }
      }
      _lastCapture.removeWhere((id, _) => !live.contains(id));
      _primed = true;
    } finally {
      _busy = false;
    }
  }

  void _emit(TmuxEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    if (!_events.isClosed) await _events.close();
  }
}
