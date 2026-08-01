import 'package:genesis_tree/genesis_tree.dart';

import 'perception.dart';
import 'perception_element.dart';

/// Named value leaf: `Field(name, value)` — the measurement vocabulary for a
/// single named datum.
///
/// Fills a vocabulary gap: `Node` gives a measurement its structure, but
/// earlier perception frameworks had no leaf for the values hanging off that
/// structure. A [Field] is the smallest harvestable unit — a name bound to a
/// point-in-time [value].
class Field extends Perception {
  /// Creates a named value leaf, optionally [key]ed.
  const Field(this.name, this.value, {super.key});

  /// The name of this datum within the measurement.
  final String name;

  /// The measured value at configuration time; null is a legal measurement.
  final Object? value;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    const level = DiagnosticsLevel.info;
    final value = this.value;
    properties.add(switch (value) {
      String value => DiagnosticsProperty.string(
        name: name,
        level: level,
        value: value,
      ),
      int value => DiagnosticsProperty.int(
        name: name,
        level: level,
        value: value,
      ),
      double value => DiagnosticsProperty.double(
        name: name,
        level: level,
        value: value,
      ),
      bool value => DiagnosticsProperty.flag(
        name: name,
        level: level,
        value: value,
      ),
      Enum value => DiagnosticsProperty.enumValue(
        name: name,
        level: level,
        value: value.name,
        enumType: value.runtimeType.toString(),
      ),
      Duration value => DiagnosticsProperty.duration(
        name: name,
        level: level,
        value: value,
      ),
      DateTime value => DiagnosticsProperty.timestamp(
        name: name,
        level: level,
        value: value,
      ),
      _ => DiagnosticsProperty.object(
        name: name,
        level: level,
        properties: [
          DiagnosticsProperty.string(
            name: 'value',
            level: level,
            value: value.toString(),
          ),
        ],
      ),
    });
  }

  @override
  FieldElement createElement() => FieldElement(this);
}

/// Mounted element for [Field]: a leaf — no children, no build contract, and
/// the inherited empty rebuild hook. An in-place update swaps the
/// configuration, so [field] always reports the latest measured value.
class FieldElement extends PerceptionElement {
  /// Creates the element for [seed].
  FieldElement(Field super.seed);

  /// The current [Field] configuration, typed.
  Field get field => perception as Field;
}
