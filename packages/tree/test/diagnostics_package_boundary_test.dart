import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('grid-only station lock state is absent from genesis_tree', () {
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

  test('the package has no generated or annotation-driven contract code', () {
    final packageSource = File('pubspec.yaml').readAsStringSync();
    expect(packageSource, isNot(contains('freezed')));
    expect(packageSource, isNot(contains('json_annotation')));
    expect(packageSource, isNot(contains('build_runner')));
    expect(packageSource, isNot(contains('json_serializable')));

    final library = Directory('lib');
    final generatedFiles = library
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.freezed.dart') ||
              file.path.endsWith('.g.dart'),
        );
    expect(generatedFiles, isEmpty);

    final source = library
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(source, isNot(contains('package:freezed_annotation')));
    expect(source, isNot(matches(RegExp(r'^part\s', multiLine: true))));
    expect(source, isNot(contains('@freezed')));
    expect(source, isNot(contains('@Freezed')));
  });

  test('the standalone diagnostics package is retired', () {
    expect(Directory('../diagnostics').existsSync(), isFalse);
  });
}
