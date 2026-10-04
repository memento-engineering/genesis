import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:test/test.dart';

@deriveOnly
final class _Derived {
  const _Derived();
}

@effectLeaf
final class _Leaf {
  @effect
  void start() {}
}

void main() {
  test('the marker constants are canonical const instances', () {
    expect(identical(deriveOnly, const DeriveOnly()), isTrue);
    expect(identical(effect, const EffectMarker()), isTrue);
    expect(identical(effectLeaf, const EffectLeafMarker()), isTrue);
  });

  test('the markers annotate declarations without changing them', () {
    expect(const _Derived(), isA<_Derived>());
    expect(() => _Leaf().start(), returnsNormally);
  });
}
