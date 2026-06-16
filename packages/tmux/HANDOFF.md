# genesis_tmux — build handoff

**Status:** spec **READY** · build **not started**. Reference survey complete (libtmux · tmux control-mode · iTerm2 · tmux(1) man + CHANGES · tmux-interface-rs/gotmux/tmuxp), output/event-model fork RESOLVED (hybrid), gotcha catalog + version matrix baked in below. A future build agent can execute this without re-researching.
**Home:** `genesis/packages/tmux` (package name `genesis_tmux`), genesis pub workspace.
**Origin:** relocated from the_grid's planned standalone `tmux` package (the_grid ADR-0002) → genesis, per Nico (2026-06-15). the_grid's `grid_runtime` `TmuxProvider` consumes it as a sibling-checkout **path dependency** (the same pattern the_grid uses for lenny's `exploration_contract`). Recorded as the_grid **ADR-0000 A34** (pending). genesis's ratified **A4** already names tmux the terminal-real-estate primitive ("grid's tmux owns the real estate; a genesis backend draws into it"), so a zero-dep tmux client is a natural genesis substrate package.

> **This is a genesis-side handoff.** The active thread is the_grid **M3** (`docs/M3-BUILD-ORDER.md`).
> genesis_tmux is M3-BUILD-ORDER **Track 1** — off the Friday critical path (the dogfood is
> `SubprocessProvider`-only) — built here so it can land independently and on its own merits.

## What it is

A standalone, general-purpose tmux client. **Zero genesis dependencies** (only `meta`). pub.dev candidate. A faithful port of gc's Go tmux client (`gascity/internal/runtime/tmux/tmux.go`, ~5.9k LOC + tests = the conformance oracle), **broadened** with cross-reference gotchas the survey collected (libtmux, tmux control-mode, iTerm2, the tmux(1) man FORMATS/CHANGES, tmux-interface-rs/gotmux/tmuxp). gc gives us "what an orchestrator actually needs + the gotchas it learned the hard way"; the survey pressure-tested gc's choices against the wider field and ADDED the gotchas gc misses (flagged per-item in the catalog).

**Its job:** a supervisor spawns and watches LONG-LIVED Claude Code agent panes — it needs Tier-1 verbs (new/kill/has/list/capture/send-keys/display-message probes), live pane OUTPUT, and session/pane LIFECYCLE events. It must be fakeable (a `TmuxExecutor` seam), version-aware, and injection-safe.

## Conventions (match the genesis sibling packages)

- Dir `packages/tmux`, pubspec `name: genesis_tmux`, `version: 0.1.0`, `resolution: workspace`, `repository: https://github.com/memento-engineering/genesis`, sdk `^3.11.0`.
- `dependencies: meta: ^1.15.0` **only** (no `genesis_*`). `dev_dependencies: lints: ^5.1.0, test: ^1.25.0`. Keep deps sorted (`sort_pub_dependencies`).
- Lints inherited from genesis root `analysis_options.yaml`: `package:lints/recommended.yaml` + strict-casts/inference/raw-types + `prefer_single_quotes` + `unawaited_futures` + **`avoid_print`** (no `print` anywhere — this includes the control-mode reader; surface diagnostics via the event Stream / a returned error, never stdout). No package-local `analysis_options` (siblings don't have one).
- Add `- packages/tmux` to the root `pubspec.yaml` `workspace:` list.
- Tests: **fakes-not-mocks**, pure-before-IO. The executor seam is the IO boundary; everything above is tested against a `FakeTmuxExecutor`. **Futures for acts, Streams for observations.**

## Architecture (gc's shape, with the observation seam widened for the hybrid)

The seam is the single most important design lesson from BOTH mature clients (gc + libtmux's in-flight `cmd()`-stable control-mode engine, PR #605): make the executor the swap point so output/events can move from poll (A) to push (B) without touching the Tier-1 verbs (identical either way). Express BOTH shapes on one injectable interface so offline tests never spawn tmux:

```dart
abstract interface class TmuxExecutor {
  /// ACTS + one-shot reads. Fake = canned (stdout, exitCode) per argv.
  Future<TmuxResult> runOnce(List<String> argv, {Duration? timeout});

  /// READ-ONLY control-mode connection (Model B). Fake = a scripted list of
  /// %-lines pushed into [lines], letting you unit-test the parser + the event
  /// Stream with zero real tmux. We only ever write refresh-client to [stdin].
  TmuxControlConn openControl(List<String> argv);
}

class TmuxControlConn {
  final Sink<String> stdin;     // we only emit refresh-client -C / -B / -A
  final Stream<String> lines;   // raw control-mode stdout lines
  final Future<void> done;      // completes on %exit / process exit
}
```

- **`ProcessTmuxExecutor`** — the only thing that shells out. `runOnce` = `Process.start('tmux', argv)` (argv list, NEVER a shell string — this is what makes us injection-safe and immune to the `;`/quoting bugs that bite tmuxinator). `openControl` = a long-lived `tmux -C` child.
- **`FakeTmuxExecutor`** — records argv + returns canned (stdout, exit); for `openControl`, returns a `TmuxControlConn` whose `lines` is a controllable Stream you push `%output`/`%window-add`/`%exit` frames into.
- **`run`/`runCtx` argv builder** — prepends `-u` (UTF-8) then `-L <socket>` (or `-S <path>`) to EVERY call (socket BEFORE the subcommand); wraps every call in a per-call timeout (gc's load-bearing 30s cap, `tmux.go:182-212,277-294`). Caller's earlier deadline wins.
- **`wrapTmuxError`** — the ONE place stderr substrings → sealed errors (gotcha #10); typed, absent-as-not-error.
- **`TmuxVersion`** — ONE `tmux -V` parser (see Version policy). Records the version (gc-style, explainable) and feeds the `has*Version` gates.
- **Two `ObservationSource` implementations behind one pair of Streams** (the resolved fork, below): `PollObservationSource` (Model A, default) and `ControlModeObservationSource` (Model B, opt-in, read-only). Both satisfy `Stream<PaneOutput> paneOutput` + `Stream<TmuxEvent> events`; consumers and the verb surface never learn which produced a frame.

## Tier-1 verbs (ADR-0004 D3 — gc-cited; identical regardless of the output-model fork)

`newSession` (`-d`, `-c <workdir>`, `-e KEY=VAL` **[≥3.2 — gate]**, command-as-initial-process, `-P -F '#{pane_id}'` to atomically learn the new pane id; `tmux.go:366-475`) · `killSession` (per-agent; NEVER `kill-session -a` on a shared socket) · `hasSession` (`-t =name` exact) · `listSessions` (`-F` with the U+241E delimiter; `-f` server-side filter) · `listPanes` (`-s -t =<sess>` — `-s` is required or you only see the active window's panes) · `capturePane` (`-p -t <pane_id> -S -<N>` bounded tail; address by captured `#{pane_id}`, fall back to `:^.0` first-window not `:0.0`; `tmux.go:2260`) · `displayMessage` probes (`#{pane_pid}`/`#{pane_current_command}`/`#{pane_dead}`/`#{pane_dead_status}`/`#{session_attached}`/`#{pane_in_mode}`; `tmux.go:1915-1973`) · `sendKeys` (literal `-l`, payload as ONE argv element — no shell quoting, never trailing bare `;` — + separate `Enter` with the "not in a mode" retry, exp backoff 500ms→2s; per-pane send serialization lock) · **long-input fallback** (load-buffer/paste-buffer `-p -d -b` for payloads >4096; `tmux.go:1496-1554` — needed to send agent prompts).

**Post-create hygiene** (run right after every `new-session -d`): `set-option -g exit-empty off` (survive a momentary zero-session window); `set-option -wt <name> window-size latest` (un-pin the 3.3+ detached 80x24 lock so capture/render is full-width). Keep `destroy-unattached` OFF (default) — headless `-d` panes are never attached.

**Safety:** session-name validation `^[a-zA-Z0-9_-]+$` + a bead-id sanitizer (`/`,`.`,`:` → `--`); the real executor always runs on a **caller-provided `-L <socket>`** (or `-S <path>`), never the default socket implicitly; refuse `kill-server`/`kill-session -a` against the default socket; pre-flight a 2s `has-session` probe before `new-session` (named-socket clobber guard, gotcha #12).

## RESOLVED — the output / event model: HYBRID (A default + read-only B opt-in)

The Tier-1 verbs above are identical regardless. Only **`paneOutput`** (live transcript) and **`events`** (session/pane lifecycle) depend on this fork. The survey verdict (convergent across libtmux, the control-mode/iTerm2 references, and the gc cross-reference): **build Model A as the default foundation, add a READ-ONLY control-mode (Model B) `ObservationSource` behind the same seam.**

### Why hybrid (recommendation)
- **Tier-1 verbs are byte-identical in A and B**, so the seam is free; keep all acts one-shot.
- **gc proves A is sufficient** (~5.9k LOC watching long-lived agent panes, zero control-mode code) and it is trivially fakeable (argv-in / string-out). Ship it first; no parser/connection-lifecycle project on the critical path.
- **B buys real PUSH** for the supervisor's two hot reactions — `%output` (an agent emitted output) and `%exit`/`%window-close` (a pane/session died) — eliminating the 100ms–1s poll latency and capture-pane churn that the LONG-LIVED workload pays continuously. The win is real precisely because panes are long-lived (one persistent connection amortizes).
- **B is READ-ONLY, always.** Under the_grid coexistence safety (ADR-0003 D6, single-writer-per-bead; any shadow experiment is read-only) and tmux#755 (control mode does NOT notify about other clients' commands → state drift), a mutating control connection is exactly the multi-writer hazard to avoid. Our `-C` client only opens, sends `refresh-client -C 80x24` (+ optional `-B` subscriptions / `-A …:continue`), and reads. gc remains the only writer. **Pure B (iTerm2's choice) is rejected:** it forces ALL acts through the persistent reply-correlation parser, needs a VT emulator over `%output` to answer "what does the pane look like" (capture-pane gives the rendered grid for free), and risks the 300s `CONTROL_MAXIMUM_AGE` hard-disconnect — a single point of failure.

This is exactly predictable-flutter's **"Futures for acts, Streams for observations"**: acts stay stateless one-shot; observations are a Stream that is poll-backed by default, push-backed when control mode is enabled and tmux≥3.2.

### Model A — `PollObservationSource` (default, concrete)
- **Live output:** attach a per-pane pipe `pipe-pane -O -o -t <pane_id> 'cat >> <fifo>'` (`-O` = pane output → command; `-o` = idempotent toggle so repeated calls don't stack pipes) and read the fifo; OR, where a fifo is undesirable, poll `capture-pane -p -t <pane_id> -S -<N>` on a bounded tail and diff. (gc itself uses capture polling, not pipe-pane; both are valid — pipe-pane is closer to a stream, capture closer to rendered state. Default to capture-poll for parity, expose pipe-pane as the lower-latency option.) Emit `PaneOutput(paneId, List<int>)`.
- **Lifecycle events:** poll `list-panes -s -a -F '<id>␞<dead>␞<dead_status>'` + `list-windows -F '#{window_activity}'` on a fixed tick (~1s; gc's death detection is `#{pane_dead}` excluding remain-on-exit corpses, `tmux.go:1954`). Diff against the last snapshot → synthesize `TmuxEvent`s.
- **Readiness:** a first-class wait primitive — poll `#{pane_current_command}`/`#{pane_dead}` on a fixed tick (gc `WaitForShellReady`/`WaitForCommand`) + a marker-poll helper (echo `__DONE__`, poll capture until it appears; libtmux `retry_until`). Output is racy in A (gotcha #16); there is no "settled" signal.

### Model B — `ControlModeObservationSource` (opt-in, read-only, ≥3.2; concrete)
- **Open** one persistent `tmux -L <socket> -C attach -t =<sess>` (or `-C new-session …` if you own creation), READ-ONLY. Immediately send `refresh-client -C 80x24` (bare WxH; control clients don't size windows otherwise). Optionally `refresh-client -B '#{pane_dead}'`-style subscriptions for poll-free scalar watches (≥3.2).
- **Parse** stdout as ONE state machine (NOT readLine-per-command):
  - `%begin <time> <cmdnum> <flags>` … `%end`/`%error <time> <cmdnum>` bracket a command-reply block; correlate to your command by the **FIFO command number** (2nd arg). We barely use replies (we only send refresh-client), but the framing must be parsed so notifications aren't mis-attributed.
  - Any `%`-line OUTSIDE a block is an async **notification**. (man guarantees: "A notification will never occur inside an output block.")
  - Treat `%begin` flags as OPAQUE; tolerate 2–3 trailing fields (gotcha #24).
- **Decode `%output %<paneid> <value>`**: un-escape octal `\ooo` (bytes <0x20 and `\` were escaped; a real backslash arrives as `\134`) → **`List<int>` bytes, NEVER a Dart String** (may be invalid UTF-8 / raw VT escapes). Emit `PaneOutput(paneId, bytes)`. Let the consumer decide UTF-8/VT.
- **Map** the lifecycle notifications to the typed union: `%window-add`→`WindowAdded`, `%window-close`→`WindowClosed`, `%window-renamed`→`WindowRenamed`, `%session-changed`/`%sessions-changed`→`SessionChanged`/`SessionsChanged`, `%pane-mode-changed`→`PaneModeChanged`, `%exit [reason]`→`Exit`. Parse-and-ignore `%unlinked-window-*`/`%client-*` (other sessions; lower priority for a single supervisor).
- **Failure handling (mandatory):**
  - `%exit` = the WHOLE connection died (server restart / session kill / desync) → reconnect AND reconcile via one-shot `list-sessions`/`list-panes`/`capture-pane` (you missed events while down).
  - Flow control: for agent panes prefer **NO pause-after** and DRAIN promptly (so you never hit the 300s `CONTROL_MAXIMUM_AGE` hard-disconnect). If you opt into pause-after, handle `%pause`/`%continue` (resume `refresh-client -A '%<pane>:continue'`) and ACCEPT that paused output is DROPPED on resume (offset resets). Cap retained bytes per pane yourself; a chatty agent floods the one shared stream.

### Event union (freezed-style sealed; Stream-emitted)
`PaneOutput(paneId, List<int> bytes)` · `WindowAdded/WindowClosed/WindowRenamed(windowId, [name])` · `SessionChanged(sessionId, name)` · `SessionsChanged()` · `PaneModeChanged(paneId)` · `Exit([reason])`. In Model A these are synthesized from poll-diffs; in Model B from push frames — same union, same Stream.

## Version policy

Centralize version handling in ONE `TmuxVersion` (libtmux pattern, NOT gc's silent assume-one-tmux): run `tmux -V`, take the token after `tmux `, strip the trailing letter (`replaceAll(RegExp('[a-z-]'), '')` so `3.2a`→`3.2`, `2.4-master` parses), handle `master`/`-rc`/openbsd suffixes; expose `hasMin/hasGte/hasGt/hasLt/hasLte`. Record the parsed version at startup (explainable). **KNOWN QUIRK:** the letter-strip makes `3.2a == 3.2` — version checks CANNOT distinguish letter-suffixed point releases (libtmux/tmuxp #199 family); never gate on a letter-only difference.

See the **Version matrix** (separate field) for the full per-flag table. Runtime gates we must apply: `new-session -e` **≥3.2** (gc's inline comment, the tmux-interface-rs table, and libtmux's 3.2a floor all corroborate 3.2 for *new-session* specifically; the `2.9`/`3.0` CHANGES entries are for new-WINDOW/split-window, NOT new-session); control-mode flow control + `refresh-client -B` subscriptions **≥3.2**; `send-keys -K` **≥3.4**; `capture-pane -T` **≥3.4** (and `-M` ≥3.6); `destroy-unattached keep-last/keep-group` **≥3.4**. Feature-PROBE `capture-pane -C` (introducing version unrecorded; gc avoids it — default plain `-p`). **Practical tested floor: tmux 3.2** (pinned dev host is 3.6b ✓). The one-shot act path works on much older tmux, so the hybrid degrades gracefully: "acts work; events fall back to polling" on ancient servers.

## Gotcha catalog

The full cross-referenced catalog (each gotcha → guard → source, with gc-corroborated vs wider-refs-ADD flagged) is in the separate `gotchaCatalog` field. The non-negotiable four that BOTH mature clients independently converged on (strongest possible signal — port verbatim): (1) `has-session` ALWAYS with `=` exact-match prefix; (2) `send-keys -l` for literal/untrusted text, as ONE argv element, with Enter sent SEPARATELY, capped at 4096; (3) validate session names (`^[a-zA-Z0-9_-]+$`, reject `.`/`:`/empty) BEFORE they reach tmux — your ids contain dots; (4) bound `capture-pane` to last-N for the live tail and timeout-guard any `-S-` full-history capture. Wider-refs ADD that gc misses: never blanket-trim capture output (#3, data loss); never end a sent string with a bare `;` (#6, tmux#1849); use a U+241E/U+001F FORMAT delimiter not tab/colon (#9); serialize sends per pane against TTY typeahead overflow (#8); explicit `tmux -V` parse + per-flag gates (version policy above).

## Tests / DoD

- **Offline (the bulk):** every verb + both stream surfaces + error mapping + name validation + version gating through `FakeTmuxExecutor`, asserting exact argv (the gc-fidelity surface). The control-mode PARSER is unit-tested by pushing canned `%begin/%end/%output/%window-add/%exit` lines (incl. octal-escaped `%output`, an interleaved notification mid-reply-stream, and a `\134` literal backslash) into a `FakeTmuxExecutor.openControl` stream and asserting the emitted `PaneOutput` bytes and `TmuxEvent` union — zero real tmux.
- **Integration (`@Tags(['integration'])` + package `dart_test.yaml`):** create/probe/sendKeys/capture/kill a real session on an **isolated `-L genesis-tmux-test-<unique>` socket**, guarded on tmux presence (self-skip if absent), `tearDown` kill-servers the socket — never touches the developer's default-socket tmux, zero orphans. A control-mode integration test opens a READ-ONLY `-C attach` against that isolated socket, sends `printf 'x\n\n'` via send-keys, and asserts a `%output` frame arrives with the blank line intact. (tmux 3.6b confirmed present on this machine.)
- A short `README.md` with a 10-line usage example.
- Green: `dart analyze packages/tmux` clean under the strict lints (incl. `avoid_print`); `dart test packages/tmux` green.

## Reference survey — complete

libtmux (one-shot-first; in-flight `cmd()`-stable control-mode engine PR #605 — the seam lesson) · tmux control-mode + iTerm2 (pure-B, rejected for us; the framing/escaping/flow-control facts) · tmux(1) man + CHANGES (verb semantics + version gates) · tmux-interface-rs (the authoritative per-flag version table) · gotmux/gotmuxcc/tmuxp/tmuxinator (API shapes + the `;`/typeahead gotchas) + gc gotcha cross-reference (`tmux.go`, the conformance oracle). Output-model recommendation, gotcha catalog, and version matrix are baked into this handoff and its companion structured fields.
