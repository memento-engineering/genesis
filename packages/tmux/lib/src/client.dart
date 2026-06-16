/// The Tier-1 verb surface — what a supervisor of long-lived agent panes
/// actually needs: create / kill / probe / list / capture / send, every call
/// argv-only (never a shell string) and bounded by a per-call timeout.
///
/// The verbs are byte-identical whether output is later observed by polling or
/// by control mode; observation lives in `ObservationSource`, not here.
library;

import 'dart:async';

import 'errors.dart';
import 'executor.dart';
import 'format.dart';
import 'models.dart';
import 'safety.dart';
import 'version.dart';

/// A tmux client bound to one [TmuxExecutor] and one explicit [TmuxSocket].
///
/// Construct with a real `ProcessTmuxExecutor` in production or a
/// `FakeTmuxExecutor` in tests; the verbs are identical either way.
class TmuxClient {
  /// Binds the client to [executor] on [socket]. [timeout] caps every call
  /// (a load-bearing 30s default); a caller passing a shorter deadline wins. A
  /// known [version] skips the `tmux -V` probe.
  TmuxClient({
    required TmuxExecutor executor,
    required TmuxSocket socket,
    Duration timeout = const Duration(seconds: 30),
    TmuxVersion? version,
  }) : _executor = executor,
       _socket = socket,
       _timeout = timeout,
       _version = version;

  final TmuxExecutor _executor;
  final TmuxSocket _socket;
  final Duration _timeout;
  TmuxVersion? _version;

  /// Serializes sends per pane so two payloads never interleave on one TTY.
  final Map<String, Future<void>> _sendChains = {};
  int _bufferSeq = 0;

  /// The socket this client is bound to.
  TmuxSocket get socket => _socket;

  /// The cached version, once probed (or supplied at construction).
  TmuxVersion? get version => _version;

  // --- argv builder ---------------------------------------------------------

  /// Runs `tmux -u <socket> <args>` with the effective timeout (the smaller of
  /// the client cap and any caller [timeout]). Returns the raw result; callers
  /// decide whether a non-zero exit is an error.
  Future<TmuxResult> _run(List<String> args, {Duration? timeout}) {
    final argv = ['-u', ..._socket.args, ...args];
    final eff = (timeout != null && timeout < _timeout) ? timeout : _timeout;
    return _executor.runOnce(argv, timeout: eff);
  }

  /// Runs as [_run], throwing the classified [TmuxException] on a non-zero
  /// exit.
  Future<TmuxResult> _runOk(List<String> args, {Duration? timeout}) async {
    final r = await _run(args, timeout: timeout);
    if (!r.ok) throw wrapTmuxError(r);
    return r;
  }

  // --- version --------------------------------------------------------------

  /// Probes `tmux -V` once and caches it. Subsequent calls return the cache.
  Future<TmuxVersion> probeVersion() async {
    final cached = _version;
    if (cached != null) return cached;
    final r = await _executor.runOnce(['-V'], timeout: _timeout);
    if (!r.ok) throw wrapTmuxError(r);
    return _version = TmuxVersion.parse(r.stdout);
  }

  // --- Tier-1 verbs ---------------------------------------------------------

  /// Creates a detached session named [name] and returns the id of its first
  /// pane (learned atomically via `-P -F '#{pane_id}'`).
  ///
  /// [workdir] sets the pane's start directory; [env] injects environment
  /// variables (requires tmux ≥ 3.2 — guarded); [command] is the initial
  /// process (defaults to the user's shell when omitted); [width]/[height]
  /// size the detached window. Runs post-create hygiene (`exit-empty off`,
  /// `window-size latest`) so a headless pane survives and captures full-width.
  Future<String> newSession({
    required String name,
    String? workdir,
    Map<String, String> env = const {},
    List<String>? command,
    int? width,
    int? height,
  }) async {
    if (!isValidSessionName(name)) {
      throw TmuxGuardException(
        reason:
            'invalid session name "$name" '
            '(allowed: letters, digits, underscore, hyphen)',
      );
    }
    if (env.isNotEmpty) {
      final v = await probeVersion();
      if (!v.supportsNewSessionEnv) {
        throw TmuxGuardException(
          reason: 'new-session -e (inline env) needs tmux >= 3.2; have $v',
        );
      }
    }
    // Named-socket clobber guard: refuse to create over a live session.
    if (await hasSession(name)) {
      throw TmuxDuplicateSession(
        name: name,
        argv: const ['new-session'],
        stderr: 'session already exists on ${_socket.label}',
      );
    }

    final args = <String>['new-session', '-d', '-s', name];
    if (workdir != null) args.addAll(['-c', workdir]);
    if (width != null) args.addAll(['-x', '$width']);
    if (height != null) args.addAll(['-y', '$height']);
    for (final entry in env.entries) {
      args.addAll(['-e', '${entry.key}=${entry.value}']);
    }
    args.addAll(['-P', '-F', '#{pane_id}']);
    if (command != null && command.isNotEmpty) args.addAll(command);

    final r = await _runOk(args);
    final paneId = r.line;

    await _postCreateHygiene(name);
    return paneId;
  }

  /// Post-create hygiene; best-effort (failures here never fail the create).
  Future<void> _postCreateHygiene(String name) async {
    // Survive a momentary zero-session window.
    await _run(['set-option', '-g', 'exit-empty', 'off']);
    // Un-pin the 3.3+ detached 80x24 lock so capture/render is full-width.
    await _run(['set-option', '-wt', '=$name', 'window-size', 'latest']);
  }

  /// Kills the session named [name] (idempotent: a missing session is a
  /// no-op). Refuses destructive shorthands (`-a`, leading-dash names).
  Future<void> killSession(String name) async {
    if (name.isEmpty || name == '-a' || name.startsWith('-')) {
      throw TmuxGuardException(
        reason: 'refusing kill-session for unsafe target "$name"',
      );
    }
    final r = await _run(['kill-session', '-t', '=$name']);
    if (r.ok) return;
    final err = wrapTmuxError(r);
    if (err is TmuxNotFound || err is TmuxNoServer) return; // already gone
    throw err;
  }

  /// Kills the tmux server on *this client's socket only*. Safe because the
  /// socket is always explicit — this can never reach the default socket.
  /// Used for test teardown.
  Future<void> killServer() async {
    final r = await _run(['kill-server']);
    if (r.ok) return;
    final err = wrapTmuxError(r);
    if (err is TmuxNoServer) return;
    throw err;
  }

  /// Whether a session named [name] exists (exact match via `=`).
  ///
  /// `has-session`'s exit code is the authoritative contract — 0 = present,
  /// non-zero = absent — across every "no server" / "no current target" /
  /// "can't find session" wording tmux uses, so this never throws on a missing
  /// session.
  Future<bool> hasSession(String name) async {
    if (name.isEmpty) return false;
    final r = await _run(['has-session', '-t', '=$name']);
    return r.ok;
  }

  /// Lists all sessions on the socket (empty when no server is running).
  Future<List<SessionInfo>> listSessions() async {
    final r = await _run([
      'list-sessions',
      '-F',
      formatSpec(SessionInfo.formatTokens),
    ]);
    if (!r.ok) {
      final err = wrapTmuxError(r);
      if (err is TmuxNoServer || err is TmuxNotFound) return const [];
      throw err;
    }
    return [for (final f in parseRecords(r.stdout)) SessionInfo.fromFields(f)];
  }

  /// Lists panes — all panes of [session] (the `-s` server-wide-within-session
  /// form, so non-active windows are included), or every pane on the socket
  /// when [session] is null.
  Future<List<PaneInfo>> listPanes({String? session}) async {
    final args = <String>['list-panes', '-s'];
    if (session != null) {
      args.addAll(['-t', '=$session']);
    } else {
      args.add('-a');
    }
    args.addAll(['-F', formatSpec(PaneInfo.formatTokens)]);
    final r = await _run(args);
    if (!r.ok) {
      final err = wrapTmuxError(r);
      if (err is TmuxNoServer || err is TmuxNotFound) return const [];
      throw err;
    }
    return [for (final f in parseRecords(r.stdout)) PaneInfo.fromFields(f)];
  }

  /// Captures pane [paneId]'s visible content, or its last [lines] of history
  /// when [lines] > 0 (a bounded tail — never an unbounded `-S -`). One
  /// trailing newline (tmux's terminator) is removed; interior blank lines are
  /// preserved.
  Future<String> capturePane(String paneId, {int lines = 0}) async {
    final args = <String>['capture-pane', '-p', '-t', paneId];
    if (lines > 0) args.addAll(['-S', '-$lines']);
    final r = await _runOk(args);
    return r.line;
  }

  /// Evaluates a `#{…}` [format] against [target] (`display-message -p`),
  /// returning the single rendered value (trailing newline stripped).
  Future<String> displayMessage(String target, String format) async {
    final r = await _runOk(['display-message', '-p', '-t', target, format]);
    return r.line;
  }

  // --- probes (built on display-message) ------------------------------------

  /// The pane's foreground process pid, or null if unavailable.
  Future<int?> panePid(String paneId) async =>
      int.tryParse(await displayMessage(paneId, '#{pane_pid}'));

  /// The command currently running in the pane.
  Future<String> paneCurrentCommand(String paneId) =>
      displayMessage(paneId, '#{pane_current_command}');

  /// Whether the pane's process has exited (`pane_dead`).
  Future<bool> paneDead(String paneId) async =>
      await displayMessage(paneId, '#{pane_dead}') == '1';

  /// The dead pane's exit status, or null when the pane is alive / unknown.
  Future<int?> paneDeadStatus(String paneId) async {
    final v = await displayMessage(paneId, '#{pane_dead_status}');
    return v.isEmpty ? null : int.tryParse(v);
  }

  /// Whether the pane is in a mode (copy mode, view mode, …) — when true, a
  /// bare `Enter` is intercepted by the mode rather than sent to the process.
  Future<bool> paneInMode(String paneId) async =>
      await displayMessage(paneId, '#{pane_in_mode}') == '1';

  /// Whether any client is attached to session [name].
  Future<bool> sessionAttached(String name) async =>
      await displayMessage('=$name', '#{session_attached}') == '1';

  // --- send-keys ------------------------------------------------------------

  /// Sends [text] to [paneId] as literal input, then `Enter` when [enter].
  ///
  /// The payload is one argv element (no shell quoting, never a trailing bare
  /// `;`), sent with `-l`. Payloads over 4096 bytes go through a paste buffer
  /// instead. Sends to the same pane are serialized so two payloads cannot
  /// interleave on the TTY. `Enter` is sent as a separate key and retried with
  /// backoff while the pane is in a mode.
  Future<void> sendKeys(String paneId, String text, {bool enter = true}) {
    final prev = _sendChains[paneId] ?? Future<void>.value();
    final run = prev.then((_) => _doSendKeys(paneId, text, enter: enter));
    // Keep the per-pane chain alive even if this send throws.
    _sendChains[paneId] = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _doSendKeys(
    String paneId,
    String text, {
    required bool enter,
  }) async {
    if (text.length > 4096) {
      await _sendViaBuffer(paneId, text);
    } else if (text.isNotEmpty) {
      await _runOk(['send-keys', '-t', paneId, '-l', text]);
    }
    if (enter) await _sendEnter(paneId);
  }

  /// Long-input fallback: stage [text] in a uniquely named buffer (one argv
  /// element, injection-safe) and paste it into the pane, deleting the buffer
  /// after. `set-buffer` is used instead of `load-buffer -` because the
  /// executor seam has no stdin channel.
  Future<void> _sendViaBuffer(String paneId, String text) async {
    final buf = 'genesis-${_bufferSeq++}';
    await _runOk(['set-buffer', '-b', buf, text]);
    await _runOk(['paste-buffer', '-p', '-d', '-b', buf, '-t', paneId]);
  }

  /// Sends a standalone `Enter`, retrying with exponential backoff
  /// (500ms → 2s) while the pane is in a mode that would swallow it.
  Future<void> _sendEnter(String paneId) async {
    const backoffs = [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ];
    for (var attempt = 0; ; attempt++) {
      if (!await paneInMode(paneId)) {
        await _runOk(['send-keys', '-t', paneId, 'Enter']);
        return;
      }
      if (attempt >= backoffs.length) {
        // Pane stayed in a mode; send anyway as a last resort.
        await _runOk(['send-keys', '-t', paneId, 'Enter']);
        return;
      }
      await Future<void>.delayed(backoffs[attempt]);
    }
  }
}
