import 'package:genesis_tree/genesis_tree.dart';

import 'perception_element.dart';

/// Immutable measurement configuration node — the domain's config base.
///
/// `Perception extends Component`: perception is a tree domain, visibly — its
/// public signatures surface tree types. It is the Widget analog of the
/// measurement domain. Pure Dart; zero Flutter imports.
///
/// `Perception` is the config base for measurement *artifacts* (containers
/// and leaves such as [Node]-style structure and `Field` values) whose
/// mounted form is a [PerceptionElement]. Composition configs
/// (`StatelessPerception`/`StatefulPerception`/`InheritedPerception`) extend
/// the tree composition layer directly — composition is tree-owned; artifact
/// semantics are domain-owned.
abstract class Perception extends Component {
  /// Creates a perception, optionally [key]ed for keyed reconciliation.
  const Perception({super.key});

  /// Creates the mounted [PerceptionElement] for this configuration — the
  /// domain name for the element factory. [createElement] bridges to it, so
  /// the tree reconciler mounts perceptions like any other [Component].
  @override
  PerceptionElement createElement();

  /// Domain alias of [Component.canUpdate]: whether a mounted element configured
  /// by [a] can be updated in place with [b].
  static bool canUpdate(Perception a, Perception b) =>
      Component.canUpdate(a, b);
}
