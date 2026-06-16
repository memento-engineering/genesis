/// A zero-dependency, injection-safe tmux client for supervising long-lived
/// panes.
///
/// Everything sits above one seam — [TmuxExecutor]. [TmuxClient] is the
/// Tier-1 verb surface (create / kill / probe / list / capture / send), every
/// call argv-only and timeout-bounded. Live output and lifecycle events arrive
/// as a [TmuxEvent] stream from an [ObservationSource], served either by
/// polling ([PollObservationSource], the default) or by a read-only control
/// connection ([ControlModeObservationSource], opt-in, tmux ≥ 3.2). Run it
/// against [ProcessTmuxExecutor] in production and [FakeTmuxExecutor] in tests
/// — the verbs and streams are identical either way.
library;

export 'src/client.dart';
export 'src/control_parser.dart';
export 'src/control_source.dart';
export 'src/errors.dart';
export 'src/events.dart';
export 'src/executor.dart';
export 'src/fake_executor.dart';
export 'src/models.dart';
export 'src/observation.dart';
export 'src/poll_source.dart';
export 'src/process_executor.dart';
export 'src/safety.dart';
export 'src/version.dart';
