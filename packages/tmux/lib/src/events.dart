/// The observation union — every frame either source can emit.
///
/// [TmuxEvent] is a sealed union so consumers switch exhaustively. The same
/// union flows whether frames are synthesized from poll-diffs (Model A) or
/// pushed from a control-mode connection (Model B); a consumer never learns
/// which produced a given frame. [PaneOutput] (live transcript bytes) is a
/// member, but also surfaces on its own filtered stream for convenience.
library;

import 'package:meta/meta.dart';

/// Root of the observation union.
@immutable
sealed class TmuxEvent {
  const TmuxEvent();
}

/// Live output from a pane. [bytes] are the exact transcript bytes (octal
/// un-escaped in Model B, diffed from a capture in Model A) — never a decoded
/// String, since they may be invalid UTF-8 or raw VT escape sequences. The
/// consumer decides interpretation.
final class PaneOutput extends TmuxEvent {
  /// Records [bytes] emitted by pane [paneId] (a `%N` id).
  const PaneOutput(this.paneId, this.bytes);

  /// The pane that emitted the bytes (tmux `%N` pane id).
  final String paneId;

  /// The raw output bytes.
  final List<int> bytes;

  @override
  String toString() => 'PaneOutput($paneId, ${bytes.length} bytes)';
}

/// A window was added (`%window-add` / poll-diff: a new window id appeared).
final class WindowAdded extends TmuxEvent {
  /// Records the new window [windowId] (a `@N` id).
  const WindowAdded(this.windowId);

  /// The tmux `@N` window id.
  final String windowId;

  @override
  String toString() => 'WindowAdded($windowId)';
}

/// A window closed (`%window-close` / poll-diff: a window id disappeared).
final class WindowClosed extends TmuxEvent {
  /// Records the closed window [windowId].
  const WindowClosed(this.windowId);

  /// The tmux `@N` window id.
  final String windowId;

  @override
  String toString() => 'WindowClosed($windowId)';
}

/// A window was renamed (`%window-renamed`).
final class WindowRenamed extends TmuxEvent {
  /// Records that window [windowId] is now named [name].
  const WindowRenamed(this.windowId, this.name);

  /// The tmux `@N` window id.
  final String windowId;

  /// The new window name.
  final String name;

  @override
  String toString() => 'WindowRenamed($windowId, "$name")';
}

/// The attached session changed (`%session-changed`).
final class SessionChanged extends TmuxEvent {
  /// Records the now-current session [sessionId] named [name].
  const SessionChanged(this.sessionId, this.name);

  /// The tmux `$N` session id.
  final String sessionId;

  /// The session name.
  final String name;

  @override
  String toString() => 'SessionChanged($sessionId, "$name")';
}

/// The set of sessions changed (`%sessions-changed`) — a coarse "re-list"
/// hint with no payload.
final class SessionsChanged extends TmuxEvent {
  /// A sessions-changed notification.
  const SessionsChanged();

  @override
  String toString() => 'SessionsChanged()';
}

/// A pane entered or left a mode such as copy mode (`%pane-mode-changed`).
final class PaneModeChanged extends TmuxEvent {
  /// Records that pane [paneId] changed mode.
  const PaneModeChanged(this.paneId);

  /// The tmux `%N` pane id.
  final String paneId;

  @override
  String toString() => 'PaneModeChanged($paneId)';
}

/// The connection ended (`%exit`) — in Model B the whole control connection
/// is gone (server restart, session kill, desync) and the consumer must
/// reconnect and reconcile. [reason] is tmux's optional explanation.
final class Exit extends TmuxEvent {
  /// Records an exit, with tmux's optional [reason].
  const Exit([this.reason]);

  /// tmux's optional reason string (null when none was given).
  final String? reason;

  @override
  String toString() => 'Exit(${reason == null ? '' : '"$reason"'})';
}
