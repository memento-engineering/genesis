// Proof-fixture Seed types bound by test/src/fixture.catalog.json.
//
// Three species, mirroring the tree package's own test fixtures (ADR-0001
// Decision 3: container artifacts live with their domains, so these stay
// test-side):
//
// - `Panel`   — keyed multichild container whose branch reconciles children
//               in `performRebuild` (the tree test-fixture Node analog);
// - `Label`   — bare leaf with required string props;
// - `Gauge`   — leaf exercising every prop kind (string / number / integer /
//               boolean / enum, required and optional-with-default) plus a
//               type-level action declaration in the catalog.
import 'package:genesis_tree/genesis_tree.dart';

/// Keyed multichild container seed.
class Panel extends Seed {
  /// Creates a panel holding [children].
  const Panel(this.name, {this.children = const [], super.key});

  /// Human-readable name of this container.
  final String name;

  /// Child configurations, reconciled by key.
  final List<Seed> children;

  @override
  PanelBranch createBranch() => PanelBranch(this);
}

/// Branch for [Panel]: a non-component branch whose artifact response in the
/// rebuild hook is keyed reconciliation of its children.
class PanelBranch extends Branch {
  /// Creates the branch for [seed].
  PanelBranch(Panel super.seed);

  List<Branch> _children = const [];

  /// The mounted child branches. Exposed for testing.
  List<Branch> get children => _children;

  Panel get _panel => seed as Panel;

  @override
  void mount(Branch? parent, Object? slot) {
    super.mount(parent, slot);
    performRebuild();
  }

  @override
  void performRebuild() {
    _children = updateChildren(_children, _panel.children);
  }

  @override
  void visitChildren(void Function(Branch child) visitor) {
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

/// Leaf seed holding a single named string value.
class Label extends Seed {
  /// Creates a label.
  const Label({required this.name, required this.value, super.key});

  /// Label identifying this value.
  final String name;

  /// Current string value.
  final String value;

  @override
  LabelBranch createBranch() => LabelBranch(this);
}

/// Branch for [Label]; the empty default rebuild hook.
class LabelBranch extends Branch {
  /// Creates the branch for [seed].
  LabelBranch(Label super.seed);
}

/// Leaf seed exercising every catalog prop kind; its catalog type also
/// declares action affordances (`set` / `reset`).
class Gauge extends Seed {
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
  GaugeBranch createBranch() => GaugeBranch(this);
}

/// Branch for [Gauge]; the empty default rebuild hook.
class GaugeBranch extends Branch {
  /// Creates the branch for [seed].
  GaugeBranch(Gauge super.seed);
}
