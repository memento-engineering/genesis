/// Static analysis rules for safe genesis tree context use.
///
/// This package is an analyzer extension: register it under `plugins:` in
/// `analysis_options.yaml` rather than importing it. The analysis server loads
/// the extension from `package:genesis_lint/main.dart`, which this library
/// re-exports so the package has a library named after itself.
library;

export 'main.dart' show LintExtension, plugin;
