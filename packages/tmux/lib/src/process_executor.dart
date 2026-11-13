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
        try {
          await Future.wait([outDone, errDone]);
        } on Object {
          // The drain after a kill may fail; the timeout is what is reported.
        }
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
    final handle = _ControlHandle();
    unawaited(_drive(argv, lines, stdinCtrl, done, handle));
    return TmuxControlConn(
      stdin: stdinCtrl.sink,
      lines: lines.stream,
      done: done.future,
      kill: handle.kill,
    );
  }

  Future<void> _drive(
    List<String> argv,
    StreamController<String> lines,
    StreamController<String> stdinCtrl,
    Completer<void> done,
    _ControlHandle handle,
  ) async {
    final Process proc;
    try {
      proc = await Process.start(executable, argv);
    } on ProcessException {
      // A kill asked for a child that never started has nothing to end.
      handle.startFailed();
      // Nothing will ever read the frames the caller writes: drain and drop
      // them, so closing the input completes instead of waiting on a reader.
      stdinCtrl.stream.listen(null);
      await _closeAndDeliver(lines);
      await stdinCtrl.close();
      if (!done.isCompleted) done.complete();
      return;
    }

    // latin1 keeps the byte stream lossless for octal-escaped %output.
    final outDone = Completer<void>();
    final outSub = proc.stdout
        .transform(latin1.decoder)
        .transform(const LineSplitter())
        .listen(
          lines.add,
          onError: (_) {},
          onDone: outDone.complete,
          cancelOnError: false,
        );
    // A kill asked for before the process existed applies now.
    handle.attach(proc);

    // Forward refresh-client frames (the only thing we ever write) to stdin.
    final inSub = stdinCtrl.stream.listen((frame) {
      try {
        proc.stdin.write(frame.endsWith('\n') ? frame : '$frame\n');
      } on Object {
        // Broken pipe after exit — the connection is ending anyway.
      }
    }, onDone: () => _closeStdin(proc));

    await proc.exitCode;
    // The exit can be observed before stdout's last bytes are read: drain the
    // pipe to its end so the child's final output is delivered, bounded in
    // case something else still holds the pipe open.
    await outDone.future.timeout(_drainBound, onTimeout: () {});
    await outSub.cancel();
    await inSub.cancel();
    await _closeAndDeliver(lines);
    await stdinCtrl.close();
    if (!done.isCompleted) done.complete();
  }

  /// How long, after the child exits, the executor keeps reading its stdout
  /// for output still in the pipe.
  static const Duration _drainBound = Duration(seconds: 1);

  /// Closes [lines]; when it has a listener, waits until every buffered line
  /// and the close itself reached it, so `done` never overtakes output.
  ///
  /// With no listener the close is not awaited, since its future completes
  /// only once the stream is read.
  static Future<void> _closeAndDeliver(StreamController<String> lines) async {
    if (lines.hasListener) {
      await lines.close();
    } else {
      unawaited(lines.close());
    }
  }

  /// Closes the child's real stdin so tmux sees EOF; a broken pipe after the
  /// child already exited is ignored.
  static void _closeStdin(Process proc) => unawaited(_closeStdinQuietly(proc));

  /// Closes [proc]'s stdin, swallowing a synchronous throw and an
  /// asynchronous failure alike.
  static Future<void> _closeStdinQuietly(Process proc) async {
    try {
      await proc.stdin.close();
    } on Object {
      // The child is already gone.
    }
  }
}

/// The kill switch for one control-mode child, which may not exist yet when
/// the kill is asked for.
class _ControlHandle {
  Process? _proc;
  bool _killRequested = false;
  bool _startFailed = false;

  /// Sends SIGKILL to the child, or remembers the request until it starts.
  void kill() {
    final proc = _proc;
    if (proc != null) {
      proc.kill(ProcessSignal.sigkill);
    } else if (!_startFailed) {
      _killRequested = true;
    }
  }

  /// Binds the started [proc], applying a kill asked for before it existed.
  void attach(Process proc) {
    _proc = proc;
    if (_killRequested) proc.kill(ProcessSignal.sigkill);
  }

  /// Records that the child never started, so a later kill is a no-op.
  void startFailed() {
    _startFailed = true;
    _killRequested = false;
  }
}
