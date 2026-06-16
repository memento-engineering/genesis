# genesis_tmux

A **zero-dependency, injection-safe tmux client** for supervising long-lived
panes — the verbs a process supervisor actually needs (create / kill / probe /
list / capture / send), plus a live stream of pane output and lifecycle events,
all behind one fakeable seam.

Built for the job of spawning and watching long-lived agent panes: it needs the
core verbs, live pane **output**, and session/pane **lifecycle** events; it must
be **fakeable**, **version-aware**, and **injection-safe**. Only dependency:
`meta`.

## The seam

Everything sits above one interface, [`TmuxExecutor`]:

- **`ProcessTmuxExecutor`** — the only thing that shells out. Every call is
  `Process.start('tmux', argv)` with an argv **list**, never a shell string —
  which is what makes the client immune to the `;`/quoting/`=`-expansion bugs
  that bite shell-string clients.
- **`FakeTmuxExecutor`** — records argv and returns canned results, with a
  scriptable control-mode connection. The whole client (verbs, version gates,
  error mapping, both observation sources, the control-mode parser) is testable
  in pure Dart, offline.

```dart
import 'package:genesis_tmux/genesis_tmux.dart';

final client = TmuxClient(
  executor: const ProcessTmuxExecutor(),
  socket: const TmuxSocket.named('my-supervisor'), // always explicit
);

final pane = await client.newSession(name: 'agent-1', workdir: '/work');
await client.sendKeys(pane, 'echo hello');          // literal + Enter
final text = await client.capturePane(pane, lines: 200);
final alive = !await client.paneDead(pane);
await client.killSession('agent-1');
```

## Acts are Futures; observations are a Stream

The verbs are stateless one-shot `Future`s. Live output and lifecycle events
arrive as a `Stream<TmuxEvent>` from an `ObservationSource`, in one of two
shapes behind the same interface — a consumer never learns which produced a
frame:

- **`PollObservationSource`** (Model A, the default) — diffs `list-panes`
  snapshots for lifecycle and `capture-pane` tails for output. No parser, no
  connection lifecycle; trivially fakeable. Output is approximate (a rendered
  grid, not a byte stream).
- **`ControlModeObservationSource`** (Model B, opt-in, tmux ≥ 3.2) — one
  **read-only** `tmux -C` connection that pushes byte-exact `%output` and
  lifecycle notifications with no poll latency. It only ever sends
  `refresh-client`; your other code remains the single writer.

```dart
final source = PollObservationSource(client: client);
await source.start();
source.paneOutput.listen((o) => stdout.add(o.bytes));
source.events.listen((e) => print(e)); // WindowAdded, WindowClosed, Exit, …
```

## Safety, by construction

- **Explicit socket, always.** A `TmuxSocket` (`-L name` or `-S path`) is
  required, so a stray `kill-server` can never reach the default socket.
- **Session-name allowlist.** `^[a-zA-Z0-9_-]+$`, validated before a name
  reaches tmux; `sanitizeBeadId` rewrites `/`, `.`, `:` to `--`.
- **Literal, one-element sends.** `send-keys -l` with the payload as a single
  argv element, `Enter` sent separately (never a trailing bare `;`), per-pane
  serialized, with a paste-buffer fallback for payloads over 4096 bytes.
- **Typed errors.** One `wrapTmuxError` maps tmux stderr into a sealed
  `TmuxException` union; a missing session is reported as absence, not thrown.

## Version awareness

`TmuxVersion.parse` reads `tmux -V` once and answers every feature gate
(`new-session -e` ≥ 3.2, `send-keys -K` ≥ 3.4, …). The one-shot verbs work on
much older tmux, so the client degrades gracefully: acts work everywhere; events
fall back to polling when control mode is unavailable. Practical tested floor:
tmux 3.2.

> Pre-1.0 and experimental; APIs may change before 1.0.
