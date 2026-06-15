import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:genesis_typesetting/genesis_typesetting.dart';

import '../console.g.dart';

/// Default surface width when the wire `screen` omits it.
const int defaultScreenWidth = 60;

/// Default surface height when the wire `screen` omits it.
const int defaultScreenHeight = 16;

/// Assembles the console's component registry over [sink].
///
/// Composes the generated [componentRegistry] (box / text / counter) with a
/// hand-written `screen` entry that maps the wire root to a typesetting [Stage].
/// `screen` is deliberately not a catalog type — [Stage] requires a runtime
/// [Sink] with no wire representation — so its factory closes over [sink] here,
/// the only place the terminal I/O is known. Every other type stays on the
/// generated, in-sync path.
ComponentRegistry consoleRegistry(Sink<List<int>> sink) => ComponentRegistry(
  catalogName: componentRegistry.catalogName,
  catalogVersion: componentRegistry.catalogVersion,
  entries: {
    ...componentRegistry.entries,
    'screen': RegistryEntry(
      container: true,
      knownProps: const {'width', 'height'},
      build: (props, children, key) => Stage(
        width: Props.integerOr('screen', props, 'width', defaultScreenWidth),
        height: Props.integerOr('screen', props, 'height', defaultScreenHeight),
        sink: sink,
        children: children,
        key: key,
      ),
    ),
  },
);
