# Changelog

## 0.1.0

- Initial release: a zero-dependency, injection-safe tmux client. One-shot
  acts (`newSession`/`killSession`/`hasSession`/`listSessions`/`listPanes`/
  `capturePane`/`sendKeys`/`displayMessage` probes) plus a unified observation
  surface — `paneOutput` and lifecycle `events` — served either by polling
  (Model A, default) or by a read-only control-mode connection (Model B,
  opt-in, tmux ≥ 3.2). Everything sits above a single `TmuxExecutor` seam, so
  the whole client is fakeable offline with `FakeTmuxExecutor`.

  Pre-1.0 and experimental; APIs may change before 1.0.
