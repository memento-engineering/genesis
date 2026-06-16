/// Value types returned by the list/probe verbs.
///
/// Each carries a `fields`-style factory that parses one delimited `-F`
/// record (see `format.dart`) so the verb layer and the poll observation
/// source decode list output the same way.
library;

import 'package:meta/meta.dart';

/// One row of `list-sessions`.
@immutable
class SessionInfo {
  /// Constructs a session row.
  const SessionInfo({
    required this.id,
    required this.name,
    required this.attached,
    required this.windows,
  });

  /// Parses the field list produced by [SessionInfo.formatTokens], in order.
  factory SessionInfo.fromFields(List<String> f) => SessionInfo(
    id: f[0],
    name: f[1],
    attached: (int.tryParse(f[2]) ?? 0) > 0,
    windows: int.tryParse(f[3]) ?? 0,
  );

  /// The `#{…}` tokens this row decodes, in field order.
  static const List<String> formatTokens = [
    '#{session_id}',
    '#{session_name}',
    '#{session_attached}',
    '#{session_windows}',
  ];

  /// The tmux `$N` session id.
  final String id;

  /// The session name.
  final String name;

  /// Whether any client is attached (`session_attached` > 0).
  final bool attached;

  /// Number of windows in the session.
  final int windows;

  @override
  String toString() =>
      'SessionInfo($id "$name", windows=$windows, attached=$attached)';
}

/// One row of `list-panes`.
@immutable
class PaneInfo {
  /// Constructs a pane row.
  const PaneInfo({
    required this.id,
    required this.windowId,
    required this.pid,
    required this.active,
    required this.dead,
    required this.deadStatus,
    required this.currentCommand,
  });

  /// Parses the field list produced by [PaneInfo.formatTokens], in order.
  factory PaneInfo.fromFields(List<String> f) => PaneInfo(
    id: f[0],
    windowId: f[1],
    pid: int.tryParse(f[2]) ?? -1,
    active: (int.tryParse(f[3]) ?? 0) > 0,
    dead: (int.tryParse(f[4]) ?? 0) > 0,
    deadStatus: f[5].isEmpty ? null : int.tryParse(f[5]),
    currentCommand: f[6],
  );

  /// The `#{…}` tokens this row decodes, in field order.
  static const List<String> formatTokens = [
    '#{pane_id}',
    '#{window_id}',
    '#{pane_pid}',
    '#{pane_active}',
    '#{pane_dead}',
    '#{pane_dead_status}',
    '#{pane_current_command}',
  ];

  /// The tmux `%N` pane id.
  final String id;

  /// The `@N` id of the window this pane belongs to.
  final String windowId;

  /// The pane's foreground process pid (-1 when unknown).
  final int pid;

  /// Whether this is the active pane in its window.
  final bool active;

  /// Whether the pane's process has exited (a corpse, with `remain-on-exit`).
  final bool dead;

  /// The dead process's exit status, when [dead] and tmux reported one.
  final int? deadStatus;

  /// The command currently running in the pane (`pane_current_command`).
  final String currentCommand;

  @override
  String toString() =>
      'PaneInfo($id in $windowId, cmd="$currentCommand"'
      '${dead ? ', dead${deadStatus == null ? '' : '($deadStatus)'}' : ''})';
}
