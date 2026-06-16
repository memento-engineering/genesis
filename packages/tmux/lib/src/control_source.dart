/// Model B — the opt-in observation source: one read-only control connection.
///
/// Opens a single persistent `tmux -C attach` (read-only — we send only
/// `refresh-client`), parses the control stream once, and pushes `%output`
/// and lifecycle notifications as [TmuxEvent]s. This buys real PUSH for the
/// supervisor's two hot reactions (output arrived, a pane/session died) and
/// eliminates poll latency, amortized over long-lived panes. Requires tmux
/// ≥ 3.2; the verbs are unchanged, so a server too old for this degrades to
/// [PollObservationSource].
///
/// On `%exit` the *whole* connection is gone (server restart, session kill,
/// desync): this source surfaces an [Exit] event, closes, and leaves
/// reconnect-and-reconcile (re-list / re-capture to recover missed events) to
/// the supervisor above it.
library;

import 'dart:async';

import 'control_parser.dart';
import 'events.dart';
import 'executor.dart';
import 'observation.dart';
import 'safety.dart';

/// Pushes [TmuxEvent]s from a read-only control-mode connection.
class ControlModeObservationSource implements ObservationSource {
  /// Observes [session] on [socket] via [executor]. [width]/[height] size the
  /// control client (control clients are unsized otherwise, so `%output` would
  /// be empty). [subscriptions] are optional `refresh-client -B` argument
  /// strings (tmux ≥ 3.2) for poll-free scalar watches.
  ControlModeObservationSource({
    required TmuxExecutor executor,
    required TmuxSocket socket,
    required String session,
    int width = 80,
    int height = 24,
    List<String> subscriptions = const [],
  }) : _executor = executor,
       _socket = socket,
       _session = session,
       _width = width,
       _height = height,
       _subscriptions = subscriptions;

  final TmuxExecutor _executor;
  final TmuxSocket _socket;
  final String _session;
  final int _width;
  final int _height;
  final List<String> _subscriptions;

  final StreamController<TmuxEvent> _events =
      StreamController<TmuxEvent>.broadcast();
  final ControlModeParser _parser = ControlModeParser();

  TmuxControlConn? _conn;
  StreamSubscription<String>? _linesSub;

  @override
  Stream<TmuxEvent> get events => _events.stream;

  @override
  Stream<PaneOutput> get paneOutput =>
      _events.stream.where((e) => e is PaneOutput).cast<PaneOutput>();

  @override
  Future<void> start() async {
    final argv = ['-u', ..._socket.args, '-C', 'attach', '-t', '=$_session'];
    final conn = _executor.openControl(argv);
    _conn = conn;

    _linesSub = conn.lines.listen((line) {
      for (final ev in _parser.feed(line)) {
        _emit(ev);
      }
    });

    // Size the control client so it receives output, then optionally subscribe.
    conn.stdin.add('refresh-client -C ${_width}x$_height');
    for (final spec in _subscriptions) {
      conn.stdin.add('refresh-client -B $spec');
    }

    // The connection ending closes us; a %exit already arrived as an event.
    unawaited(conn.done.then((_) => close()));
  }

  void _emit(TmuxEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  Future<void> close() async {
    await _linesSub?.cancel();
    _linesSub = null;
    _conn?.stdin.close();
    _conn = null;
    if (!_events.isClosed) await _events.close();
  }
}
