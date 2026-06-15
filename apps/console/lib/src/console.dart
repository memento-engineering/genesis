import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:genesis_consent/genesis_consent.dart';
import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

import 'registry.dart';

/// The offline driver that wires the genesis stack into one terminal surface:
/// it deserializes A2UI v0.9 `updateComponents` through the component registry,
/// renders the live tree to a character grid, and routes client actions through
/// `genesis_consent`'s enforce/reject substrate.
///
/// The render pipeline emits frames on a scheduled microtask after mount, so
/// every method that can change the surface yields the microtask queue before
/// returning — a synchronous caller would otherwise observe a stale grid.
class Console {
  Console._(this._surface, this._router);

  /// The wire type of the root component (`id == "root"`); maps to the render
  /// [Stage]. Fixed for the surface's lifetime.
  static const String rootType = 'screen';

  final DialogueSurface _surface;
  final ConsentRouter _router;
  bool _mounted = false;

  /// Creates a console rendering to [sink].
  ///
  /// Parses the console catalog, assembles the registry, and asserts the
  /// catalog's type names are all backed by the registry (the `screen` root is
  /// registry-only by design — it affords nothing and is not addressable).
  static Future<Console> create({required Sink<List<int>> sink}) async {
    final catalog = Catalog.parse(await _loadCatalogJson());
    final registry = consoleRegistry(sink);
    final missing = [
      for (final type in catalog.types)
        if (!registry.entries.containsKey(type.name)) type.name,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'catalog/registry drift: catalog types $missing have no registry entry',
      );
    }
    final surface = DialogueSurface(registry: registry, owner: TreeOwner());
    return Console._(
      surface,
      ConsentRouter(surface: surface, catalog: catalog),
    );
  }

  /// The mounted surface id, or null before the first [loadOrApply].
  String? get surfaceId => _surface.surfaceId;

  /// The live render grid as text (front buffer), or empty before mount.
  String snapshot() {
    final root = _surface.rootBranch;
    return root is StageBranch ? root.grid.frontToString() : '';
  }

  /// The number of render flush passes since mount (frame 0 excluded), or zero
  /// before mount. Unlike a byte-counting sink — which skips a pass whose diff
  /// is empty — this counts every pass, so it detects a rebuild that emitted no
  /// visible change (e.g. a rejection path that erroneously rebuilt the tree).
  int get flushCount {
    final root = _surface.rootBranch;
    return root is StageBranch ? root.flushCount : 0;
  }

  /// Mounts [messageJson] on the first call, then reconciles each subsequent
  /// message by key. Enforces the root-type-stability precondition: the surface
  /// root must always be type [rootType] (a render root cannot change type
  /// across re-emissions), so a violating message is rejected before it reaches
  /// the surface.
  Future<void> loadOrApply(Object messageJson) async {
    final message = parseUpdateComponents(messageJson);
    final root = message.components.where((c) => c.id == 'root');
    if (root.isEmpty) {
      throw ArgumentError('updateComponents has no "root" component');
    }
    if (root.first.type != rootType) {
      throw ArgumentError(
        'console root must be type "$rootType" (got "${root.first.type}"): '
        'the render root is fixed for the surface lifetime',
      );
    }
    if (_mounted) {
      _router.apply(message);
    } else {
      _router.mount(message);
      _mounted = true;
    }
    await _drain();
  }

  /// Routes a client action through consent and returns the structured outcome,
  /// yielding the render microtask so a follow-up [snapshot] reflects it.
  Future<ConsentOutcome> route(ActionEvent event) async {
    final outcome = _router.route(event);
    await _drain();
    return outcome;
  }

  /// A human-readable dump of the live branch tree (key : type, mounted state).
  String treeDump() {
    final root = _router.rootBranch;
    if (root == null) return '(nothing mounted)';
    final out = StringBuffer();
    void walk(Branch branch, int depth) {
      final tag = branch.mounted ? '' : ' (unmounted)';
      out.writeln(
        '${'  ' * depth}${branch.key ?? '·'} : '
        '${branch.seed.runtimeType}$tag',
      );
      branch.visitChildren((child) => walk(child, depth + 1));
    }

    walk(root, 0);
    return out.toString();
  }

  // Frames emit on a scheduled microtask; a timer-backed zero delay completes
  // after the microtask queue drains, so the surface is up to date on return.
  Future<void> _drain() => Future<void>.delayed(Duration.zero);

  static Future<String> _loadCatalogJson() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:genesis_console/console.catalog.json'),
    );
    if (uri == null) {
      throw StateError(
        'cannot resolve package:genesis_console/console.catalog.json',
      );
    }
    return File.fromUri(uri).readAsString();
  }
}
