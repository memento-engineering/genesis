# Changelog

## 0.1.2

- Fix: a render container's internal child wrapper no longer reuses the child
  component's key, so a key-based lookup against the tree (e.g. resolving a
  component id to its branch) finds exactly one branch per id. Keyed reconcile
  is unchanged — the wrapper now carries a distinct, namespaced key internally.

## 0.1.1

- Docs: package documentation (README, dartdoc) made self-contained for pub.dev; no API changes.

## 0.1.0

- Initial release: the bare-VM cell/ANSI render-branch backend — Stage/Box/Text with double-buffered diff emission.

  Pre-1.0 and experimental; APIs may change before 1.0.
