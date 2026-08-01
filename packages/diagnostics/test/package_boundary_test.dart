import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('grid-only station lock state is absent from genesis_diagnostics', () {
    final library = Directory('lib');
    final dartFiles = library
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final source = dartFiles.map((file) => file.readAsStringSync()).join('\n');
    expect(File('lib/src/station_lock_record.dart').existsSync(), isFalse);
    expect(source, isNot(contains('class StationLockRecord')));
    expect(source, isNot(contains('stationTreeBearerProtocolPrefix')));
  });
}
