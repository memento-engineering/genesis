# Spike 1 — headless Flutter render-tree dump

**Proven:** the FULL Flutter framework runs to completion in a plain shell with no
window or GUI. `flutter test` launches the `flutter_tester` headless engine shell;
inside it the real pipeline executes end-to-end: widgets -> elements -> render
objects, with real layout producing concrete geometry. The captured dump
(`output.log`) shows a root `_ReusableRenderView` configured at
`BoxConstraints(w=800.0, h=600.0)` at 3.0x DPR (physical `Size(2400.0, 1800.0)`),
a `RenderFlex` for the Column with real `parentData: offset=Offset(0.0, 56.0)`
(i.e. positioned below the laid-out AppBar), and `RenderParagraph` nodes with
concrete `size: Size(199.5, 20.0)` — text was actually shaped and measured, not
just constructed. `debugDumpRenderTree()` prints the whole laid-out tree to
stdout, and targeted probes (`tester.renderObject` + `localToGlobal`) read exact
sizes/offsets programmatically (grep `SPIKE1:` in `output.log`). This de-risks
genesis A4: headless real Flutter is viable as a conformance oracle.

**Re-run:** from the repo root:
`cd packages/exploration_flutter && flutter test test/spike/headless_render_dump_spike_test.dart`
(output was captured with `> ../../spikes/spike1_headless_dump/output.log 2>&1`).
Surprises: (1) the root render object is `_ReusableRenderView` (a test-binding
subclass of `RenderView`), and on multi-view bindings it's reached via
`tester.binding.renderViews.single`, not a `renderView` getter; (2) the dump line
`debug mode enabled - macos` reflects the host-derived `defaultTargetPlatform`
reported by flutter_tester — there is still no window; (3) text metrics are
host-renderer dependent (199.5 logical px wide here), so an oracle comparing
exact text geometry must pin fonts (flutter_test uses the bundled Ahem-style
FlutterTest font by default, which keeps metrics deterministic).
