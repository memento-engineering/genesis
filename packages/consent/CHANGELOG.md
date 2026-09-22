# Changelog

## 0.2.0

- **Breaking:** action routing now exposes and traverses canonical `Element` values; migrate `ConsentRouter.rootBranch` to `rootElement`. The deprecated forwarding getter remains, and routing gates, outcomes, and wire fields are unchanged.

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev; corrected the README's `Actionable`-on-element dispatch example.
- Reworded an action-dispatch `StateError` message (text only; no behavior change).

## 0.1.0

- Initial release: the enforce/reject action substrate — hit-test the live tree against catalog affordances; enforce via the element Actionable seam or refuse with a structured, side-effect-free outcome.

  Pre-1.0 and experimental; APIs may change before 1.0.
