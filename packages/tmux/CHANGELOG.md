# Changelog

## Unreleased

- **Breaking:** `ControlModeObservationSource` now throws an `ArgumentError`
  at construction for a subscription containing a control character
  (U+0000–U+001F, U+007F), `;` or `'`, and sends each accepted subscription
  to tmux single-quoted, as one `refresh-client -B` argument. Migration: pass
  each `refresh-client -B` spec as a single value without those characters;
  a spec with spaces now needs no extra quoting.

## 0.1.0

- Initial release: a zero-dependency, injection-safe tmux client. One-shot
  acts (`newSession`/`killSession`/`hasSession`/`listSessions`/`listPanes`/
  `capturePane`/`sendKeys`/`displayMessage` probes) plus a unified observation
  surface — `paneOutput` and lifecycle `events` — served either by polling
  (Model A, default) or by a read-only control-mode connection (Model B,
  opt-in, tmux ≥ 3.2). Everything sits above a single `TmuxExecutor` seam, so
  the whole client is fakeable offline with `FakeTmuxExecutor`.

  Pre-1.0 and experimental; APIs may change before 1.0.
