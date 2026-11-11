# Changelog

## Unreleased

- **Breaking:** `ControlModeObservationSource` now throws an `ArgumentError`
  at construction for a subscription containing a control character
  (U+0000–U+001F, U+007F), `;` or `'`, and sends each accepted subscription
  to tmux single-quoted, as one `refresh-client -B` argument. Migration: pass
  each `refresh-client -B` spec as a single value without those characters;
  a spec with spaces now needs no extra quoting.
- **Breaking:** `TmuxControlConn` has a new required `kill` member, so a
  custom `TmuxExecutor` must supply a function that forcibly terminates its
  control-mode child. Its `done` now completes once that child has exited
  (or failed to start). Migration: pass a `kill` that ends the child.
- `ControlModeObservationSource.close()` now owns the tmux child's exit: it
  closes the child's stdin, waits for the child to exit, kills it when it has
  not exited two seconds after stdin closed, delivers output that arrived
  before the exit, then closes the event stream. Every repeated call —
  including the one the connection ending makes — shares one completion.
- `ProcessTmuxExecutor` now delivers EOF to tmux when a control connection's
  stdin is closed, so the control client exits instead of lingering.
- `FakeControlConn` records stdin closes (`stdinCloses`, `stdinClosed`) and
  kills (`kills`), and can model a child that ignores stdin closing
  (`exitsOnStdinClose: false`, or `FakeTmuxExecutor`'s
  `controlExitsOnStdinClose: false`).

## 0.1.0

- Initial release: a zero-dependency, injection-safe tmux client. One-shot
  acts (`newSession`/`killSession`/`hasSession`/`listSessions`/`listPanes`/
  `capturePane`/`sendKeys`/`displayMessage` probes) plus a unified observation
  surface — `paneOutput` and lifecycle `events` — served either by polling
  (Model A, default) or by a read-only control-mode connection (Model B,
  opt-in, tmux ≥ 3.2). Everything sits above a single `TmuxExecutor` seam, so
  the whole client is fakeable offline with `FakeTmuxExecutor`.

  Pre-1.0 and experimental; APIs may change before 1.0.
