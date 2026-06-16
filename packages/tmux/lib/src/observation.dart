/// The observation seam: live pane output and lifecycle events behind one
/// pair of streams, independent of how they are produced.
///
/// `PollObservationSource` (Model A) synthesizes frames from poll-diffs;
/// `ControlModeObservationSource` (Model B) pushes them from a read-only
/// control connection. A consumer codes against this interface and never
/// learns which is behind it — exactly "Futures for acts, Streams for
/// observations", with the Stream poll-backed by default and push-backed when
/// control mode is enabled.
library;

import 'events.dart';

/// A source of [TmuxEvent]s for a tmux server.
abstract interface class ObservationSource {
  /// Every observation, in arrival order, including [PaneOutput].
  Stream<TmuxEvent> get events;

  /// The [PaneOutput] frames only — a filtered view of [events].
  Stream<PaneOutput> get paneOutput;

  /// Begins observing. For the poll source this primes a baseline and starts
  /// the tick; for control mode it opens the connection and subscribes.
  Future<void> start();

  /// Stops observing and releases resources (timer / connection / streams).
  Future<void> close();
}
