/// The ONE place tmux version handling lives — parse `tmux -V` once, record
/// it, and answer every feature gate from it.
///
/// Parsing follows the field-tested rule: take the token after `tmux `, strip
/// the trailing letter and any word suffix (`replaceAll(RegExp('[a-z-]'),
/// '')`), so `3.2a` → `3.2` and `2.4-master` → `2.4`. `master`/`next-*` with
/// no numeric core sorts as the newest possible version (every gate open).
///
/// KNOWN QUIRK: the letter strip makes `3.2a == 3.2` — a gate can never
/// distinguish letter-suffixed point releases, so never gate on one.
library;

import 'package:meta/meta.dart';

/// A parsed tmux version, comparable by `(major, minor)`.
@immutable
class TmuxVersion implements Comparable<TmuxVersion> {
  /// Constructs a version directly. Prefer [TmuxVersion.parse] for real
  /// `tmux -V` output.
  const TmuxVersion(
    this.major,
    this.minor, {
    this.isMaster = false,
    this.raw = '',
  });

  /// Parses the output of `tmux -V` (e.g. `tmux 3.6b`, `tmux next-3.4`,
  /// `tmux master`). Falls back to an [isMaster] "newest" version when no
  /// numeric core survives the strip.
  factory TmuxVersion.parse(String output) {
    final trimmed = output.trim();
    // Take the last whitespace-separated token: handles both `tmux 3.6b` and
    // a bare `3.6b`.
    final token = trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).last;
    // Strip letters and hyphens: `3.2a` -> `3.2`, `next-3.4` -> `3.4`,
    // `2.4-master` -> `2.4`, `master` -> ``.
    final cleaned = token.replaceAll(RegExp('[a-z-]'), '');
    final parts = cleaned.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return TmuxVersion(0, 0, isMaster: true, raw: trimmed);
    }
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TmuxVersion(major, minor, raw: trimmed);
  }

  /// Major version (the `3` in `3.6`).
  final int major;

  /// Minor version (the `6` in `3.6`).
  final int minor;

  /// True for an unnumbered `master`/`next` build — treated as newer than any
  /// numbered release so every feature gate is open.
  final bool isMaster;

  /// The raw `tmux -V` output this was parsed from (explainability).
  final String raw;

  @override
  int compareTo(TmuxVersion other) {
    if (isMaster || other.isMaster) {
      if (isMaster && other.isMaster) return 0;
      return isMaster ? 1 : -1;
    }
    final byMajor = major.compareTo(other.major);
    return byMajor != 0 ? byMajor : minor.compareTo(other.minor);
  }

  /// This version is at least [other] (the common "feature landed in X" gate).
  bool hasMin(TmuxVersion other) => compareTo(other) >= 0;

  /// `>=` alias of [hasMin].
  bool hasGte(TmuxVersion other) => compareTo(other) >= 0;

  /// Strictly greater than [other].
  bool hasGt(TmuxVersion other) => compareTo(other) > 0;

  /// Strictly less than [other].
  bool hasLt(TmuxVersion other) => compareTo(other) < 0;

  /// `<=` [other].
  bool hasLte(TmuxVersion other) => compareTo(other) <= 0;

  // -- Feature gates (see the package version policy) ------------------------

  /// `new-session -e KEY=VAL` inline environment (≥ 3.2).
  bool get supportsNewSessionEnv => hasMin(v3_2);

  /// Control-mode flow control and `refresh-client -B` subscriptions (≥ 3.2).
  bool get supportsControlSubscriptions => hasMin(v3_2);

  /// `send-keys -K` (≥ 3.4).
  bool get supportsSendKeysK => hasMin(v3_4);

  /// `capture-pane -T` trim-trailing (≥ 3.4).
  bool get supportsCapturePaneTrim => hasMin(v3_4);

  /// `destroy-unattached keep-last`/`keep-group` (≥ 3.4).
  bool get supportsDestroyUnattachedKeep => hasMin(v3_4);

  @override
  bool operator ==(Object other) =>
      other is TmuxVersion &&
      other.major == major &&
      other.minor == minor &&
      other.isMaster == isMaster;

  @override
  int get hashCode => Object.hash(major, minor, isMaster);

  @override
  String toString() => isMaster ? 'tmux master' : 'tmux $major.$minor';
}

/// tmux 3.2 — the practical tested floor (inline `new-session -e`, control
/// subscriptions).
const TmuxVersion v3_2 = TmuxVersion(3, 2);

/// tmux 3.4 — `send-keys -K`, `capture-pane -T`, `destroy-unattached keep-*`.
const TmuxVersion v3_4 = TmuxVersion(3, 4);

/// tmux 3.6 — `capture-pane -M`.
const TmuxVersion v3_6 = TmuxVersion(3, 6);
