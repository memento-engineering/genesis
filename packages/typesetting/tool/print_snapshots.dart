// Regenerates the snapshot literals in test/src/snapshots.dart.
//
// Run from the package root, eyeball the output, then paste:
//   dart run tool/print_snapshots.dart
import 'dart:io';

import '../test/src/fixtures.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

Future<void> main() async {
  final fx = LocalityFixture();
  final typesetter = Typesetter(
    delegate: BoxDelegate(width: 40),
    width: 40,
    height: 12,
    sink: RecordingSink(),
  );
  typesetter.mount(fx.root);
  stdout.writeln('--- initialSnapshot ---');
  stdout.writeln(typesetter.grid.frontToString());

  Future<void> pump() => Future<void>.delayed(Duration.zero);
  for (final v in [1, 2, 3, 42, 137]) {
    fx.ticker.add(v);
    await pump();
  }
  fx.feed.add('done');
  await pump();

  stdout.writeln('--- finalSnapshot ---');
  stdout.writeln(typesetter.grid.frontToString());
  typesetter.dispose();
  await fx.dispose();
}
