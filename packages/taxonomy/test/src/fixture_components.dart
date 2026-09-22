// Proof-fixture Component types bound by test/src/fixture.catalog.json.
//
// Three species, mirroring the tree package's own test fixtures (ADR-0001
// Decision 3: container artifacts live with their domains, so these stay
// test-side):
//
// - `Panel`   — keyed multichild container whose element reconciles children
//               in `performRebuild` (the tree test-fixture Node analog);
// - `Label`   — bare leaf with required string props;
// - `Gauge`   — leaf exercising every prop kind (string / number / integer /
//               boolean / enum, required and optional-with-default) plus a
//               type-level action declaration in the catalog.
import 'package:genesis_tree/genesis_tree.dart';

/// Keyed multichild container component.
class Panel extends Component {
  /// Creates a panel holding [children].
  const Panel(this.name, {this.children = const [], super.key});

  /// Human-readable name of this container.
  final String name;

  /// Child configurations, reconciled by key.
  final List<Component> children;

  @override
  PanelElement createElement() => PanelElement(this);
}

/// Element for [Panel]: a non-component element whose artifact response in the
/// rebuild hook is keyed reconciliation of its children.
class PanelElement extends Element {
  /// Creates the element for [component].
  PanelElement(Panel super.component);

  List<Element> _children = const [];

  /// The mounted child elements. Exposed for testing.
  List<Element> get children => _children;

  Panel get _panel => component as Panel;

  @override
  void mount(Element? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, _panel.children);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
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

/// Leaf component holding a single named string value.
class Label extends Component {
  /// Creates a label.
  const Label({required this.name, required this.value, super.key});

  /// Label identifying this value.
  final String name;

  /// Current string value.
  final String value;

  @override
  LabelElement createElement() => LabelElement(this);
}

/// Element for [Label]; the empty default rebuild hook.
class LabelElement extends Element {
  /// Creates the element for [component].
  LabelElement(Label super.component);
}

/// Leaf component exercising every catalog prop kind; its catalog type also
/// declares action affordances (`set` / `reset`).
class Gauge extends Component {
  /// Creates a gauge.
  const Gauge(
    this.label, {
    required this.value,
    this.scale = 10,
    this.enabled = true,
    this.align = 'start',
    super.key,
  });

  /// Text shown beside the gauge (required string, positional).
  final String label;

  /// Current reading (required number).
  final double value;

  /// Full-scale reading (optional integer, catalog default 10).
  final int scale;

  /// Whether the gauge responds to actions (optional boolean, catalog
  /// default true).
  final bool enabled;

  /// Needle alignment (optional enum start|center|end, catalog default
  /// 'start').
  final String align;

  @override
  GaugeElement createElement() => GaugeElement(this);
}

/// Element for [Gauge]; the empty default rebuild hook.
class GaugeElement extends Element {
  /// Creates the element for [component].
  GaugeElement(Gauge super.component);
}
