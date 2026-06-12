/// Demo driver: a scripted ~10-frame animation through the real live loop,
/// emitting real ANSI to stdout (pipe-safe: write-only, no terminal queries,
/// no raw mode) with per-frame stats lines on stderr.
///
/// Run on a real terminal to watch the boxes update in place:
///   dart run bin/demo.dart --demo
///
/// This file is also the consumer documentation for the paint seam: it
/// defines its own domain (Panel/Readout artifacts + a fixed-rect
/// PaintDelegate), because typesetting itself knows no node types.
library;

import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

Future<void> main(List<String> args) async {
  if (!args.contains('--demo')) {
    stderr.writeln('usage: dart run bin/demo.dart --demo');
    exitCode = 2;
    return;
  }

  final ticker = StreamController<int>();
  final feed = StreamController<String>();
  final root = Panel(
    'root',
    children: [
      Watch<int>(
        ticker.stream,
        (v) => Panel(
          'ticker',
          children: [
            Readout('count', '$v', key: 'count'),
            Readout('square', '${v * v}', key: 'square'),
          ],
        ),
        initialValue: 0,
        key: 'ticker',
      ),
      const StaticAboutBox(key: 'about'),
      Watch<String>(
        feed.stream,
        (msg) => Panel('feed', children: [Readout('last', msg, key: 'last')]),
        initialValue: '(none)',
        key: 'feed',
      ),
    ],
  );

  var totalBytes = 0;
  final typesetter = Typesetter(
    delegate: DemoDelegate(width: 44),
    width: 44,
    height: 12,
    sink: stdout,
    onFrame: (f) {
      totalBytes += f.bytesEmitted;
      final ids = [for (final r in f.repainted) r.id]..sort();
      stderr.writeln(
        'typesetting: frame=${f.index} rebuilt=${f.rebuilt.length} '
        'regions=$ids changedCells=${f.cellsChanged} '
        'ansiBytes=${f.bytesEmitted}',
      );
    },
  );

  // Screen setup is the embedder's choice: clear + home, write-only.
  stdout.write('\x1b[2J\x1b[H');
  typesetter.mount(root); // frame 0: full scene

  Future<void> step(void Function() fire) async {
    fire();
    // Sleep only — lets the event + flush microtasks run, and animates the
    // scene when watched on a live terminal. Content is fully scripted.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  await step(() => ticker.add(1)); //  1
  await step(() => feed.add('booting')); //  2
  await step(() => ticker.add(2)); //  3
  await step(() => ticker.add(3)); //  4
  await step(() => feed.add('render loop live')); //  5
  await step(() => ticker.add(3)); //  6  duplicate -> zero-byte frame
  await step(() => ticker.add(42)); //  7
  await step(() => feed.add('diffing only')); //  8
  await step(() => ticker.add(137)); //  9
  await step(() => feed.add('done')); // 10

  // Park the cursor below the scene and reset style (embedder teardown).
  stdout.write('\x1b[${typesetter.grid.height + 1};1H\x1b[0m');
  await stdout.flush();

  final updateFrames = typesetter.frames.skip(1).toList();
  final updateBytes = updateFrames.fold<int>(
    0,
    (sum, f) => sum + f.bytesEmitted,
  );
  final fullRedraw = typesetter.encoder.fullRedrawBytes(typesetter.grid);
  stderr.writeln(
    'typesetting: summary frames=${typesetter.frames.length} '
    'totalAnsiBytes=$totalBytes updateFrames=${updateFrames.length} '
    'updateAnsiBytes=$updateBytes fullRedrawBytesPerFrame=$fullRedraw',
  );

  typesetter.dispose();
  await ticker.close();
  await feed.close();
}

// ---------------------------------------------------------------------------
// The demo's domain — typesetting knows none of these types.
// ---------------------------------------------------------------------------

/// Keyed multichild container with a display name.
class Panel extends Seed {
  const Panel(this.name, {this.children = const [], super.key});
  final String name;
  final List<Seed> children;
  @override
  PanelBranch createBranch() => PanelBranch(this);
}

/// Branch for [Panel]: keyed reconciliation of its children.
class PanelBranch extends Branch {
  PanelBranch(Panel super.seed);

  List<Branch> _children = const [];

  Panel get panel => seed as Panel;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, panel.children);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  @override
  void unmount() {
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}

/// Leaf `name: value` line.
class Readout extends Seed {
  const Readout(this.name, this.value, {super.key});
  final String name;
  final String value;
  @override
  ReadoutBranch createBranch() => ReadoutBranch(this);
}

/// Branch for [Readout]; the empty default rebuild hook.
class ReadoutBranch extends Branch {
  ReadoutBranch(Readout super.seed);
}

/// Static middle box — never rebuilt by any stream event.
class StaticAboutBox extends StatelessSeed {
  const StaticAboutBox({super.key});

  @override
  Seed build(TreeContext context) => const Panel(
    'about',
    children: [
      Readout('package', 'genesis_typesetting', key: 'package'),
      Readout('backend', 'cells -> minimal ANSI', key: 'backend'),
    ],
  );
}

/// Fixed-rect delegate: one full-width box per direct child of the root.
class DemoDelegate extends PaintDelegate {
  DemoDelegate({required this.width, this.boxHeight = 4});

  final int width;
  final int boxHeight;

  final List<Branch> _topChildren = [];
  final List<Region> _regions = [];

  @override
  List<Region> assignRegions(Branch root) {
    _topChildren.clear();
    _regions.clear();
    root.visitChildren(_topChildren.add);
    for (var i = 0; i < _topChildren.length; i++) {
      _regions.add(Region(i, Rect(0, i * boxHeight, width, boxHeight)));
    }
    return List.of(_regions);
  }

  @override
  Region? regionFor(Branch rebuilt) {
    for (var i = 0; i < _topChildren.length; i++) {
      if (subtreeContains(_topChildren[i], rebuilt)) return _regions[i];
    }
    return null;
  }

  @override
  void paint(CellGrid grid, Region region) {
    final index = region.id as int;
    final rect = region.rect;
    for (var y = rect.y; y < rect.y + rect.h; y++) {
      for (var x = rect.x; x < rect.x + rect.w; x++) {
        grid.set(x, y, Cell.blank);
      }
    }
    final panelBranch = _resolvePanel(_topChildren[index]);
    if (panelBranch == null) {
      grid.putText(rect.x, rect.y, '<unrenderable>');
      return;
    }
    final color = 2 + index * 2; // green / cyan / yellow-ish accents
    grid.drawBox(
      rect.x,
      rect.y,
      rect.w,
      rect.h,
      title: panelBranch.panel.name,
      fg: color,
    );
    final lines = _contentLines(panelBranch);
    final maxLen = rect.w - 4;
    for (var j = 0; j < lines.length && j < rect.h - 2; j++) {
      var line = lines[j];
      if (line.length > maxLen) line = line.substring(0, maxLen);
      grid.putText(rect.x + 2, rect.y + 1 + j, line);
    }
  }

  PanelBranch? _resolvePanel(Branch branch) {
    var current = branch;
    for (;;) {
      if (current is PanelBranch) return current;
      Branch? sole;
      var count = 0;
      current.visitChildren((child) {
        sole = child;
        count += 1;
      });
      if (count != 1) return null;
      current = sole!;
    }
  }

  List<String> _contentLines(PanelBranch panelBranch) {
    final lines = <String>[];
    void visit(Branch branch) {
      final config = branch.seed;
      if (config is Readout) {
        lines.add('${config.name}: ${config.value}');
        return;
      }
      branch.visitChildren(visit);
    }

    panelBranch.visitChildren(visit);
    return lines;
  }
}
