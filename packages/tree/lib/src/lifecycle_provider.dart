import 'package:genesis_tree/genesis_tree.dart';

/// Creates the participant a [LifecycleProvider] owns.
///
/// The callback is argument-free so construction cannot receive a persistent
/// tree capability. Tree values are supplied only to the participant's
/// lifecycle hooks through their call-scoped readers.
// dart format off
typedef LifecycleProviderCreate<T extends TreeLifecycleParticipant> = T Function();
// dart format on

/// Drives tree lifecycle hooks for a long-lived object that is not a [Seed].
///
/// The default constructor creates and owns one participant per mount. The
/// [.value] constructor adopts an externally owned participant. Both forms
/// initialize the participant and track its inherited dependencies; only a
/// participant created by this provider is disposed by the tree.
final class LifecycleProvider<T extends TreeLifecycleParticipant>
    extends SingleChildStatefulSeed {
  /// Creates and owns a participant for the lifetime of this mount.
  const LifecycleProvider({
    required LifecycleProviderCreate<T> create,
    super.child,
    super.key,
  }) : _create = create,
       _value = null;

  /// Adopts an externally owned [value] without taking disposal ownership.
  const LifecycleProvider.value(T value, {super.child, super.key})
    : _value = value,
      _create = null;

  final LifecycleProviderCreate<T>? _create;
  final T? _value;

  @override
  SingleChildState<LifecycleProvider<T>> createState() =>
      _LifecycleProviderState<T>();

  @override
  SingleChildStatefulBranch createBranch() => _LifecycleProviderBranch<T>(this);
}

final class _LifecycleProviderState<T extends TreeLifecycleParticipant>
    extends SingleChildState<LifecycleProvider<T>> {
  late final TreeLifecyclePhaseGuard Function() _guard;
  late final T _participant;
  late final bool _created;
  _TreeDependencyScope? _dependencyScope;
  bool _ownsParticipant = false;

  TreeLifecyclePhaseGuard get _lifecyclePhaseGuard => _guard();

  @override
  void initState() {
    final create = seed._create;
    final created = create != null;
    final participant = created ? create() : seed._value!;
    _participant = participant;
    _created = created;
    _ownsParticipant = created;

    final reader = _LifecycleSnapshotReader(context, _lifecyclePhaseGuard);
    try {
      participant.initState(reader);
    } finally {
      reader._revoke();
    }
  }

  @override
  void didChangeDependencies() {
    _dependencyScope?._invalidate();
    final scope = _TreeDependencyScope();
    _dependencyScope = scope;
    final reader = _LifecycleWatchingReader(context, _lifecyclePhaseGuard);
    try {
      _participant.didChangeDependencies(reader, scope);
    } finally {
      reader._revoke();
    }
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final created = _created;
    if ((seed._create != null) != created) {
      throw StateError(
        'LifecycleProvider<$T> changed between create: and .value while '
        'reconciling in place. The provider kind is fixed for a mounted '
        'branch; change the type or key to remount instead.',
      );
    }

    final participant = _participant;
    if (!created && !identical(seed._value, participant)) {
      throw StateError(
        'LifecycleProvider<$T>.value replaced its participant while '
        'reconciling in place. Participant identity is fixed for a mounted '
        'branch; change the type or key to remount instead.',
      );
    }

    return Provider<T>.value(participant, child: child);
  }

  @override
  void dispose() => _disposeLifecycle();

  void _disposeLifecycle() {
    final dependencyScope = _dependencyScope;
    _dependencyScope = null;
    dependencyScope?._invalidate();
    _disposeOwnedParticipant();
  }

  void _disposeOwnedParticipant() {
    if (!_ownsParticipant) return;
    _ownsParticipant = false;
    _participant.dispose();
  }
}

final class _LifecycleProviderBranch<T extends TreeLifecycleParticipant>
    extends SingleChildStatefulBranch {
  _LifecycleProviderBranch(super.seed) {
    (state as _LifecycleProviderState<T>)._guard = () =>
        owner!.lifecyclePhaseGuard;
  }

  bool _mountBuild = true;

  @override
  void performRebuild() {
    if (!_mountBuild) {
      super.performRebuild();
      return;
    }
    _mountBuild = false;
    try {
      super.performRebuild();
    } catch (error, stackTrace) {
      try {
        owner!.lifecyclePhaseGuard.runInPhase<void>(
          TreeLifecyclePhase.dispose,
          (state as _LifecycleProviderState<T>)._disposeLifecycle,
        );
      } finally {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }
}

final class _TreeDependencyScope implements TreeDependencyScope {
  bool _isCurrent = true;

  @override
  bool get isCurrent => _isCurrent;

  void _invalidate() => _isCurrent = false;
}

abstract base class _LifecycleReader {
  _LifecycleReader(this._context, this._guard, this._requiredPhase);

  final TreeContext _context;
  final TreeLifecyclePhaseGuard _guard;
  final TreeLifecyclePhase _requiredPhase;
  bool _active = true;

  void _revoke() => _active = false;

  void _checkActive(String operation) {
    final currentPhase = _guard.phase;
    if (_active && currentPhase == _requiredPhase) return;
    throw StateError(
      '$operation requires an active call in $_requiredPhase; the reader is '
      '${_active ? 'active' : 'revoked'} and the current phase is '
      '$currentPhase.',
    );
  }
}

final class _LifecycleSnapshotReader extends _LifecycleReader
    implements TreeSnapshotReader {
  _LifecycleSnapshotReader(TreeContext context, TreeLifecyclePhaseGuard guard)
    : super(context, guard, TreeLifecyclePhase.initState);

  @override
  T? read<T extends Object>() {
    _checkActive('TreeSnapshotReader.read<$T>()');
    return _context.read<T>();
  }
}

final class _LifecycleWatchingReader extends _LifecycleReader
    implements TreeWatchingReader {
  _LifecycleWatchingReader(TreeContext context, TreeLifecyclePhaseGuard guard)
    : super(context, guard, TreeLifecyclePhase.didChangeDependencies);

  @override
  T? watch<T extends Object>() {
    _checkActive('TreeWatchingReader.watch<$T>()');
    return _context.watch<T>();
  }
}
