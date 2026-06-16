/// Injection and footgun guards that run *before* anything reaches tmux.
///
/// Two converge across every mature tmux client: a strict session-name
/// allowlist (your ids carry dots/colons that tmux would mis-parse as
/// window/pane addresses) and an explicit, never-default socket. Both are
/// enforced here so the verb layer can assume clean inputs.
library;

import 'package:meta/meta.dart';

/// Allowed session-name shape: letters, digits, underscore, hyphen — nothing
/// tmux reads as an address (`.`, `:`) or a target sigil (`=`, `@`, `%`, `$`).
final RegExp _sessionNamePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// Whether [name] is a safe tmux session name (non-empty, allowlist only).
bool isValidSessionName(String name) =>
    name.isNotEmpty && _sessionNamePattern.hasMatch(name);

/// Rewrites a bead/agent id into a safe session name by mapping `/`, `.`, and
/// `:` to `--` (the separators that would otherwise read as tmux addresses).
/// The result is *not* guaranteed valid on its own — pass it through
/// [isValidSessionName] if the source can contain other characters.
String sanitizeBeadId(String id) => id.replaceAll(RegExp(r'[/.:]'), '--');

/// Where a tmux server lives. Always explicit — the client never touches the
/// default socket implicitly, so a stray `kill-server` can never reach a
/// developer's real tmux.
@immutable
sealed class TmuxSocket {
  const TmuxSocket();

  /// A named socket under tmux's socket directory (`tmux -L <name>`).
  const factory TmuxSocket.named(String name) = NamedSocket;

  /// A socket at an explicit filesystem path (`tmux -S <path>`).
  const factory TmuxSocket.path(String path) = PathSocket;

  /// The flags that select this socket, placed before the subcommand.
  List<String> get args;

  /// A label for diagnostics.
  String get label;
}

/// A named socket: `tmux -L <name>`.
final class NamedSocket extends TmuxSocket {
  /// Selects the socket named [name].
  const NamedSocket(this.name);

  /// The socket name (a bare name, not a path).
  final String name;

  @override
  List<String> get args => ['-L', name];

  @override
  String get label => '-L $name';
}

/// A path socket: `tmux -S <path>`.
final class PathSocket extends TmuxSocket {
  /// Selects the socket at [path].
  const PathSocket(this.path);

  /// The filesystem path of the socket.
  final String path;

  @override
  List<String> get args => ['-S', path];

  @override
  String get label => '-S $path';
}
