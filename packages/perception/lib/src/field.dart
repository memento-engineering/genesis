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
