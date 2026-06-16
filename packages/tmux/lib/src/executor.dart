/// The IO boundary: a single injectable seam every higher layer runs through.
///
/// Acts and one-shot reads go through [TmuxExecutor.runOnce] (a [Future] —
/// argv in, [TmuxResult] out); a live read-only control-mode connection comes
/// from [TmuxExecutor.openControl] (a [TmuxControlConn] — a Stream of raw
/// control-mode lines). Real tmux lives behind `ProcessTmuxExecutor`; tests
/// drive everything through `FakeTmuxExecutor`, so nothing above this seam
/// ever spawns a process.
library;

import 'package:meta/meta.dart';

/// The captured result of one `tmux` invocation.
@immutable
class TmuxResult {
  /// Records the [argv] that ran and the process [exitCode], [stdout], and
  /// [stderr] it produced.
  const TmuxResult({
    required this.argv,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The full argument vector passed to `tmux` (without the executable name).
  final List<String> argv;

  /// The process exit code; 0 on success.
  final int exitCode;

  /// Decoded standard output.
  final String stdout;

  /// Decoded standard error.
  final String stderr;

  /// Whether the invocation exited cleanly.
  bool get ok => exitCode == 0;

  /// [stdout] with a single trailing newline removed (tmux appends one to
  /// every `display-message`/`-p` read); never trims interior content.
  String get line =>
      stdout.endsWith('\n') ? stdout.substring(0, stdout.length - 1) : stdout;

  @override
  String toString() =>
      'TmuxResult(${argv.join(' ')} -> exit $exitCode'
      '${stderr.isEmpty ? '' : ', stderr: ${stderr.trim()}'})';
}

/// A live, read-only control-mode connection (`tmux -C`).
///
/// We only ever write `refresh-client` frames to [stdin]; [lines] carries raw
/// control-mode stdout, one line per element (the `%begin`/`%output`/`%exit`
/// framing the parser consumes). [done] completes when the connection ends
/// (a `%exit` notification or the child process exiting).
@immutable
class TmuxControlConn {
  /// Wraps the [stdin] sink, [lines] stream, and [done] future of one
  /// control-mode child.
  const TmuxControlConn({
    required this.stdin,
    required this.lines,
    required this.done,
  });

  /// Where `refresh-client` frames are written. We never send mutating
  /// commands — the control connection is read-only by construction.
  final Sink<String> stdin;

  /// Raw control-mode stdout, line-split. Bytes are preserved losslessly
  /// (latin1) so octal-escaped `%output` payloads round-trip exactly.
  final Stream<String> lines;

  /// Completes when the connection ends (`%exit` or process exit).
  final Future<void> done;
}

/// The one swap point between real tmux and a fake.
///
/// Every higher layer — the Tier-1 verbs, the version probe, both observation
/// sources — is expressed against this interface, so they are byte-identical
/// whether output is polled or pushed and whether tmux is real or faked.
abstract interface class TmuxExecutor {
  /// Runs one `tmux` invocation to completion. [argv] is the argument vector
  /// after the executable name (the caller has already prepended `-u`, the
  /// socket flags, and the subcommand). [timeout], when given, bounds the
  /// call; an implementation that times out should surface it as a
  /// `TmuxTimeoutException` rather than hanging.
  Future<TmuxResult> runOnce(List<String> argv, {Duration? timeout});

  /// Opens a long-lived, read-only control-mode connection for [argv] (an
  /// `attach`/`new-session` argv already carrying `-C`). The returned
  /// connection's [TmuxControlConn.lines] streams raw control-mode output.
  TmuxControlConn openControl(List<String> argv);
}
