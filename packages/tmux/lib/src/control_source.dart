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
  /// strings (tmux ≥ 3.2) for poll-free scalar watches. An entry containing a
  /// control character (U+0000–U+001F, U+007F), `;` or `'` is rejected with
  /// an [ArgumentError], and each entry is sent to tmux as one single-quoted
  /// argument.
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
       _subscriptions = _checkSubscriptions(subscriptions);

  /// Returns an unmodifiable copy of [subscriptions], throwing an
  /// [ArgumentError] for the first entry holding a control character, DEL,
  /// `;` or `'` — any of which could end the `refresh-client -B` frame early.
  static List<String> _checkSubscriptions(List<String> subscriptions) {
    for (final entry in subscriptions) {
      for (final unit in entry.codeUnits) {
        if (unit <= 0x1F || unit == 0x7F || unit == 0x3B || unit == 0x27) {
          final hex = unit.toRadixString(16).toUpperCase().padLeft(4, '0');
          throw ArgumentError.value(
            entry,
            'subscriptions',
            'contains forbidden character U+$hex',
          );
        }
      }
    }
    return List<String>.unmodifiable(subscriptions);
  }

  final TmuxExecutor _executor;
  final TmuxSocket _socket;
  final String _session;
  final int _width;
  final int _height;
  final List<String> _subscriptions;

  final StreamController<TmuxEvent> _events =
      StreamController<TmuxEvent>.broadcast();
  final ControlModeParser _parser = ControlModeParser();

  /// How long [close] waits for the child to exit after closing its stdin
  /// before killing it.
  static const Duration _exitBound = Duration(seconds: 2);

  TmuxControlConn? _conn;
  StreamSubscription<String>? _linesSub;
  Future<void>? _closing;

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
      // Validated free of `'` and line breaks, so the quote cannot close
      // early: one command, one `-B` argument.
      conn.stdin.add("refresh-client -B '$spec'");
    }

    // The connection ending closes us; a %exit already arrived as an event.
    unawaited(() async {
      await conn.done;
      await close();
    }());
  }

  void _emit(TmuxEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  /// Stops observing and ends the tmux control child.
  ///
  /// Closes the child's stdin, then waits for the child to exit. A child that
  /// has not exited two seconds after its stdin closed is killed, and the
  /// close waits for that exit too, so a completed close never leaves the
  /// child running. Output the child delivered before exiting is emitted;
  /// only then does the source stop reading and close [events].
  ///
  /// Idempotent: every call — including the one the connection ending makes
  /// — returns the same future, and the work runs once. On a source that was
  /// never started it only closes [events].
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final conn = _conn;
    if (conn != null) {
      conn.stdin.close();
      try {
        await conn.done.timeout(_exitBound);
      } on TimeoutException {
        conn.kill();
        // A killed child always exits; wait for it without a bound.
        await conn.done;
      }
      // Let lines the connection already delivered be parsed and emitted.
      await Future<void>.delayed(Duration.zero);
      await _linesSub?.cancel();
      _linesSub = null;
    }
    if (!_events.isClosed) await _events.close();
  }
}
