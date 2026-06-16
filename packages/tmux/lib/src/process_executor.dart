/// The real executor — the only thing in the package that spawns a process.
///
/// Every call is `Process.start(executable, argv)` with an argv *list*, never
/// a shell string: this is what makes the client injection-safe and immune to
/// the `;`/quoting bugs that bite shell-string clients. Control mode reads
/// stdout as latin1 so octal-escaped `%output` bytes round-trip losslessly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'executor.dart';

/// A [TmuxExecutor] backed by a real `tmux` binary.
class ProcessTmuxExecutor implements TmuxExecutor {
  /// Binds to the `tmux` [executable] (a name resolved on `PATH`, or an
  /// absolute path).
  const ProcessTmuxExecutor({this.executable = 'tmux'});

  /// The tmux executable to launch.
  final String executable;

  @override
  Future<TmuxResult> runOnce(List<String> argv, {Duration? timeout}) async {
    final Process proc;
    try {
      proc = await Process.start(executable, argv);
    } on ProcessException catch (e) {
      throw TmuxBinaryNotFound(
        executable: executable,
        argv: List<String>.of(argv),
        cause: e,
      );
    }

    final out = <int>[];
    final err = <int>[];
    final outDone = proc.stdout.forEach(out.addAll);
    final errDone = proc.stderr.forEach(err.addAll);
    await proc.stdin.close();

    int exitCode;
    if (timeout != null) {
      try {
        exitCode = await proc.exitCode.timeout(timeout);
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
        await proc.exitCode; // reap
        await Future.wait([outDone, errDone]).catchError((_) => <void>[]);
        throw TmuxTimeoutException(
          argv: List<String>.of(argv),
          timeout: timeout,
        );
      }
    } else {
      exitCode = await proc.exitCode;
    }

    await Future.wait([outDone, errDone]);
    return TmuxResult(
      argv: List<String>.of(argv),
      exitCode: exitCode,
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
    );
  }

  @override
  TmuxControlConn openControl(List<String> argv) {
    final lines = StreamController<String>();
    final stdinCtrl = StreamController<String>();
    final done = Completer<void>();
    unawaited(_drive(argv, lines, stdinCtrl, done));
    return TmuxControlConn(
      stdin: stdinCtrl.sink,
      lines: lines.stream,
      done: done.future,
    );
  }

  Future<void> _drive(
    List<String> argv,
    StreamController<String> lines,
    StreamController<String> stdinCtrl,
    Completer<void> done,
  ) async {
    final Process proc;
    try {
      proc = await Process.start(executable, argv);
    } on ProcessException {
      await lines.close();
      await stdinCtrl.close();
      if (!done.isCompleted) done.complete();
      return;
    }

    // latin1 keeps the byte stream lossless for octal-escaped %output.
    final outSub = proc.stdout
        .transform(latin1.decoder)
        .transform(const LineSplitter())
        .listen(lines.add, onError: (_) {});

    // Forward refresh-client frames (the only thing we ever write) to stdin.
    final inSub = stdinCtrl.stream.listen((frame) {
      try {
        proc.stdin.write(frame.endsWith('\n') ? frame : '$frame\n');
      } on Object {
        // Broken pipe after exit — the connection is ending anyway.
      }
    });

    await proc.exitCode;
    await outSub.cancel();
    await inSub.cancel();
    await lines.close();
    await stdinCtrl.close();
    if (!done.isCompleted) done.complete();
  }
}
