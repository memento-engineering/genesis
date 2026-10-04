// ignore_for_file: non_constant_identifier_names

import 'package:genesis_lint/src/rules/derive_dont_construct.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/tree_rule_test.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DeriveDontConstructRuleTest);
  });
}

const _postureSource = r'''
import 'package:genesis_foundation/genesis_foundation.dart';

@deriveOnly
final class Posture {
  const Posture({required this.tier});

  const Posture.cheap() : this(tier: 0);

  factory Posture.parse(String text) => Posture(tier: text.length);

  final int tier;

  Posture copyWith({int? tier}) => Posture(tier: tier ?? this.tier);
}

@DeriveOnly()
base class Bundle {
  Bundle(this.size);

  final int size;
}

final class Plain {
  const Plain();
}
''';

@reflectiveTest
final class DeriveDontConstructRuleTest extends TreeRuleTest {
  @override
  void setUp() {
    rule = DeriveDontConstructRule();
    super.setUp();
    newFile('$testPackageLibPath/posture.dart', _postureSource);
  }

  Future<void> test_bare_constructions_from_another_library() async {
    const source = r'''
import 'posture.dart';

const fixed = Posture(tier: 1);
final named = Posture.cheap();
final parsed = Posture.parse('x');
final bundle = Bundle(2);
final tearOff = Posture.new;
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('Posture(tier'), 'Posture'.length),
      lint(source.indexOf('Posture.cheap'), 'Posture.cheap'.length),
      lint(source.indexOf('Posture.parse'), 'Posture.parse'.length),
      lint(source.indexOf('Bundle(2)'), 'Bundle'.length),
      lint(source.indexOf('Posture.new'), 'Posture.new'.length),
    ]);
  }

  Future<void> test_super_constructor_from_another_library() async {
    const source = r'''
import 'posture.dart';

final class LargeBundle extends Bundle {
  LargeBundle() : super(10);
}
''';
    await assertDiagnostics(source, [
      lint(source.indexOf('super(10)'), 'super(10)'.length),
    ]);
  }

  Future<void> test_message_names_the_class() async {
    const source = r'''
import 'posture.dart';

final bundle = Bundle(2);
''';
    await assertDiagnostics(source, [
      lint(
        source.indexOf('Bundle(2)'),
        'Bundle'.length,
        messageContainsAll: ["'Bundle'"],
      ),
    ]);
  }

  Future<void> test_derivation_from_another_library_is_silent() async {
    await assertNoDiagnostics(r'''
import 'posture.dart';

Posture raise(Posture ambient) => ambient.copyWith(tier: ambient.tier + 1);

const plain = Plain();
''');
  }

  Future<void>
  test_construction_inside_the_declaring_library_is_silent() async {
    await assertNoDiagnosticsInFile('$testPackageLibPath/posture.dart');
  }

  Future<void> test_construction_inside_a_part_is_silent() async {
    newFile('$testPackageLibPath/value.dart', r'''
import 'package:genesis_foundation/genesis_foundation.dart';

part 'value_parts.dart';

@deriveOnly
final class Value {
  const Value();
}
''');
    final part = '$testPackageLibPath/value_parts.dart';
    newFile(part, r'''
part of 'value.dart';

const origin = Value();
''');
    await assertNoDiagnosticsInFile(part);
  }

  Future<void> test_same_named_annotation_elsewhere_is_silent() async {
    newFile('$testPackageLibPath/markers.dart', r'''
final class DeriveOnly {
  const DeriveOnly();
}

const deriveOnly = DeriveOnly();

@deriveOnly
final class Lookalike {
  const Lookalike();
}
''');
    await assertNoDiagnostics(r'''
import 'markers.dart';

const value = Lookalike();
''');
  }
}
