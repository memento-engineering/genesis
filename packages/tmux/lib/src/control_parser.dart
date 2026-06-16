/// The control-mode line parser — one synchronous state machine, no IO.
///
/// [feed] takes one raw control-mode line and returns zero or more
/// [TmuxEvent]s. `%begin … %end`/`%error` bracket a command-reply block; any
/// `%`-line *outside* a block is an async notification (the man page
/// guarantees a notification never occurs inside a block). We send only
/// `refresh-client`, so reply payloads are parsed for framing but their
/// content is ignored — the framing matters so a notification is never
/// mis-attributed to a reply.
///
/// Being a pure function of (state, line), the parser is unit-tested by
/// pushing canned lines and asserting the emitted events — zero real tmux.
library;

import 'events.dart';
import 'format.dart';

/// Stateful control-mode line parser. One instance per connection.
class ControlModeParser {
  bool _inBlock = false;

  /// Whether the parser is currently inside a `%begin … %end` reply block.
  bool get inBlock => _inBlock;

  /// Feeds one raw line; returns the events it produced (often none).
  List<TmuxEvent> feed(String line) {
    if (_inBlock) {
      if (_isBlockClose(line)) _inBlock = false;
      return const []; // reply payload + markers: framing only, content ignored
    }
    if (line.startsWith('%begin')) {
      _inBlock = true;
      return const [];
    }
    if (!line.startsWith('%')) return const []; // stray, ignore
    return _notification(line);
  }

  bool _isBlockClose(String line) =>
      line == '%end' ||
      line == '%error' ||
      line.startsWith('%end ') ||
      line.startsWith('%error ');

  List<TmuxEvent> _notification(String line) {
    final firstSpace = line.indexOf(' ');
    final kw = firstSpace < 0 ? line : line.substring(0, firstSpace);
    switch (kw) {
      case '%output':
        return [_output(line)];
      case '%window-add':
        return [WindowAdded(_firstArg(line))];
      case '%window-close':
        return [WindowClosed(_firstArg(line))];
      case '%window-renamed':
        final (id, rest) = _idAndRest(line);
        return [WindowRenamed(id, rest)];
      case '%session-changed':
        final (id, rest) = _idAndRest(line);
        return [SessionChanged(id, rest)];
      case '%sessions-changed':
        return const [SessionsChanged()];
      case '%pane-mode-changed':
        return [PaneModeChanged(_firstArg(line))];
      case '%exit':
        final reason = firstSpace < 0 ? null : line.substring(firstSpace + 1);
        return [Exit(reason)];
      default:
        // %unlinked-window-*, %client-*, %layout-change, %continue, %pause,
        // %subscription-changed, … — parsed and ignored for a single
        // supervisor.
        return const [];
    }
  }

  /// `%output %<pane> <data…>` — pane id is the second token, data is the
  /// (space-preserving) remainder, octal-decoded to exact bytes.
  TmuxEvent _output(String line) {
    final firstSpace = line.indexOf(' ');
    if (firstSpace < 0) return const PaneOutput('', []);
    final secondSpace = line.indexOf(' ', firstSpace + 1);
    final paneEnd = secondSpace < 0 ? line.length : secondSpace;
    final paneId = line.substring(firstSpace + 1, paneEnd);
    final data = secondSpace < 0 ? '' : line.substring(secondSpace + 1);
    return PaneOutput(paneId, octalDecode(data));
  }

  /// The single argument after the keyword (e.g. the `@N`/`%N` id).
  String _firstArg(String line) {
    final firstSpace = line.indexOf(' ');
    if (firstSpace < 0) return '';
    final secondSpace = line.indexOf(' ', firstSpace + 1);
    return secondSpace < 0
        ? line.substring(firstSpace + 1)
        : line.substring(firstSpace + 1, secondSpace);
  }

  /// The first argument (an id) plus the space-preserving remainder (a name).
  (String, String) _idAndRest(String line) {
    final firstSpace = line.indexOf(' ');
    if (firstSpace < 0) return ('', '');
    final secondSpace = line.indexOf(' ', firstSpace + 1);
    if (secondSpace < 0) return (line.substring(firstSpace + 1), '');
    return (
      line.substring(firstSpace + 1, secondSpace),
      line.substring(secondSpace + 1),
    );
  }
}
