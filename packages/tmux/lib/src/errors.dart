/// Structured error hierarchy for genesis_tmux.
///
/// [wrapTmuxError] is the ONE place tmux stderr substrings become typed
/// members of the [TmuxException] union, so call sites switch exhaustively
/// instead of string-matching stderr themselves. The classification is
/// *absent-as-not-error*: a "can't find session" stderr becomes a
/// [TmuxNotFound], which probe verbs like `hasSession` read as `false` rather
/// than rethrow.
library;

import 'executor.dart';

/// What kind of object tmux reported missing.
enum TmuxObject {
  /// A session (`can't find session`).
  session,

  /// A window (`can't find window`).
  window,

  /// A pane (`can't find pane`).
  pane,

  /// A client (`can't find client`).
  client,
}

/// Root of the genesis_tmux error union. Every member carries the [argv] that
/// produced it and an LLM-feedback-ready [message].
sealed class TmuxException implements Exception {
  const TmuxException();

  /// The argument vector of the call that failed.
  List<String> get argv;

  /// Human/LLM-readable description assembled from the structured fields.
  String get message;

  @override
  String toString() => message;
}

/// The `tmux` executable could not be launched at all (not on `PATH`, or the
/// configured path is wrong). Distinct from a tmux that ran and failed.
final class TmuxBinaryNotFound extends TmuxException {
  /// Records that launching [executable] failed; [cause] is the underlying
  /// OS error, when available.
  const TmuxBinaryNotFound({
    required this.executable,
    required this.argv,
    this.cause,
  });

  /// The executable name or path we tried to launch.
  final String executable;

  @override
  final List<String> argv;

  /// The underlying error from the process layer, if any.
  final Object? cause;

  @override
  String get message =>
      'could not launch "$executable" — is tmux installed and on PATH?'
      '${cause == null ? '' : ' ($cause)'}';
}

/// The call exceeded its per-call timeout and the process was killed.
final class TmuxTimeoutException extends TmuxException {
  /// Records that the call timed out after [timeout].
  const TmuxTimeoutException({required this.argv, required this.timeout});

  @override
  final List<String> argv;

  /// The deadline that fired.
  final Duration timeout;

  @override
  String get message =>
      'tmux ${argv.join(' ')} timed out after ${timeout.inMilliseconds}ms';
}

/// No tmux server is running on the target socket (`no server running on …`).
final class TmuxNoServer extends TmuxException {
  /// Records the no-server failure with the raw [stderr].
  const TmuxNoServer({required this.argv, required this.stderr});

  @override
  final List<String> argv;

  /// The verbatim stderr tmux emitted.
  final String stderr;

  @override
  String get message =>
      'no tmux server running on the target socket (${stderr.trim()})';
}

/// tmux ran and reported a named object missing (`can't find <object>`).
///
/// This is the *absent-as-not-error* member: probe verbs catch it and report
/// absence rather than propagate it.
final class TmuxNotFound extends TmuxException {
  /// Records that [object] [target] was not found.
  const TmuxNotFound({
    required this.object,
    required this.target,
    required this.argv,
    required this.stderr,
  });

  /// Which kind of object was missing.
  final TmuxObject object;

  /// The target that was looked up (e.g. `=my-session`), when known.
  final String? target;

  @override
  final List<String> argv;

  /// The verbatim stderr tmux emitted.
  final String stderr;

  @override
  String get message =>
      "tmux: can't find ${object.name}"
      '${target == null ? '' : ' "$target"'}';
}

/// A `new-session` collided with a session of the same name on the socket
/// (`duplicate session: …`).
final class TmuxDuplicateSession extends TmuxException {
  /// Records the duplicate-session collision for [name].
  const TmuxDuplicateSession({
    required this.name,
    required this.argv,
    required this.stderr,
  });

  /// The session name that already existed.
  final String name;

  @override
  final List<String> argv;

  /// The verbatim stderr tmux emitted.
  final String stderr;

  @override
  String get message => 'duplicate session "$name" on the target socket';
}

/// tmux ran and exited non-zero for a reason not matched by a more specific
/// member — the catch-all.
final class TmuxCommandFailed extends TmuxException {
  /// Records a generic non-zero exit with its [exitCode] and [stderr].
  const TmuxCommandFailed({
    required this.argv,
    required this.exitCode,
    required this.stderr,
  });

  @override
  final List<String> argv;

  /// The non-zero exit code.
  final int exitCode;

  /// The verbatim stderr tmux emitted.
  final String stderr;

  @override
  String get message =>
      'tmux ${argv.join(' ')} failed (exit $exitCode)'
      '${stderr.trim().isEmpty ? '' : ': ${stderr.trim()}'}';
}

/// A guard refused a command before it reached tmux (an invalid session name,
/// a destructive op against the default socket, …). Never produced by tmux —
/// produced by us, to stop a footgun.
final class TmuxGuardException extends TmuxException {
  /// Records why the guard refused, with the offending [argv] (which never
  /// ran).
  const TmuxGuardException({required this.reason, this.argv = const []});

  /// Why the call was refused.
  final String reason;

  @override
  final List<String> argv;

  @override
  String get message => 'refused: $reason';
}

/// Classifies a failed [TmuxResult] into a typed [TmuxException].
///
/// Call only when `!result.ok`. The matching is on lowercased stderr
/// substrings (tmux's wording is stable across the supported versions). A
/// `can't find …` becomes a [TmuxNotFound] — probe verbs decide whether that
/// is an error or simply `false`.
TmuxException wrapTmuxError(TmuxResult result) {
  final argv = result.argv;
  final stderr = result.stderr;
  final s = stderr.toLowerCase();

  if (s.contains('no server running') ||
      s.contains('error connecting') ||
      (s.contains('no such file or directory') && s.contains('socket'))) {
    return TmuxNoServer(argv: argv, stderr: stderr);
  }
  if (s.contains('duplicate session')) {
    return TmuxDuplicateSession(
      name: _quotedAfter(stderr, 'duplicate session:') ?? '',
      argv: argv,
      stderr: stderr,
    );
  }
  if (s.contains("can't find session") ||
      s.contains('session not found') ||
      // tmux says these when the server is up but the target resolves to no
      // session (e.g. zero sessions exist).
      s.contains('no current target') ||
      s.contains('no current session') ||
      s.contains('no sessions')) {
    return TmuxNotFound(
      object: TmuxObject.session,
      target: _quotedAfter(stderr, 'find session'),
      argv: argv,
      stderr: stderr,
    );
  }
  if (s.contains("can't find window")) {
    return TmuxNotFound(
      object: TmuxObject.window,
      target: _quotedAfter(stderr, 'find window'),
      argv: argv,
      stderr: stderr,
    );
  }
  if (s.contains("can't find pane")) {
    return TmuxNotFound(
      object: TmuxObject.pane,
      target: _quotedAfter(stderr, 'find pane'),
      argv: argv,
      stderr: stderr,
    );
  }
  if (s.contains("can't find client")) {
    return TmuxNotFound(
      object: TmuxObject.client,
      target: _quotedAfter(stderr, 'find client'),
      argv: argv,
      stderr: stderr,
    );
  }
  return TmuxCommandFailed(
    argv: argv,
    exitCode: result.exitCode,
    stderr: stderr,
  );
}

/// Extracts the token tmux names after [marker] (`… find session: name` or
/// `… find session name`), trimmed of a trailing colon/period; null if absent.
String? _quotedAfter(String stderr, String marker) {
  final i = stderr.toLowerCase().indexOf(marker.toLowerCase());
  if (i < 0) return null;
  var rest = stderr.substring(i + marker.length).trim();
  if (rest.startsWith(':')) rest = rest.substring(1).trim();
  if (rest.isEmpty) return null;
  final end = rest.indexOf('\n');
  final tok = (end < 0 ? rest : rest.substring(0, end)).trim();
  return tok.isEmpty ? null : tok;
}
