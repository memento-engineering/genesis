// Regenerates the snapshot literals in test/src/snapshots.dart.
//
// Run from the package root, eyeball the output, then paste:
//   dart run tool/print_snapshots.dart
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

import '../test/src/fixtures.dart';

Future<void> main() async {
  final fx = LocalityFixture(sink: RecordingSink());
  final owner = TreeOwner();
  final stage = owner.mountRoot(fx.stageSeed) as StageBranch;
  stdout.writeln('--- initialSnapshot ---');
  stdout.writeln(stage.grid.frontToString().trimRight());

  Future<void> pump() => Future<void>.delayed(Duration.zero);
  for (final v in [1, 2, 3, 42, 137]) {
    fx.ticker.add(v);
    await pump();
  }
  fx.feed.add('done');
  await pump();

  stdout.writeln('--- finalSnapshot ---');
  stdout.writeln(stage.grid.frontToString().trimRight());
  owner.dispose();
  await fx.dispose();
}
