// CI guard: forbid package:flutter imports inside tree/lib.
// tree is a pure-Dart engine package (ADR-0001 Decision 1); any flutter
// import breaks that guarantee and would prevent use in non-Flutter isolates.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('lib/ contains no package:flutter imports', () {
    final re = RegExp(r"""import\s+['"](package:flutter|flutter)[/']""");
    final dir = Directory('lib');
    if (!dir.existsSync()) {
      fail('lib/ directory not found — run dart test from packages/tree/');
    }
    final hits = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (re.hasMatch(f.readAsStringSync())) {
        hits.add(f.path);
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'package:flutter imports are forbidden in tree/lib. '
          'Offending files: $hits',
    );
  });
}
