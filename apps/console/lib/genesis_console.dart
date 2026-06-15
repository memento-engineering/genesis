/// The genesis console: an offline terminal driver that renders an A2UI v0.9
/// surface to a character grid and enforces client actions across the genesis
/// stack (tree, taxonomy, typesetting, dialogue, consent).
library;

export 'package:genesis_consent/genesis_consent.dart'
    show Applied, ConsentOutcome, Rejected, RejectionKind, ActionChange;
export 'package:genesis_dialogue/genesis_dialogue.dart' show ActionEvent;

export 'src/console.dart';
export 'src/counter.dart';
export 'src/registry.dart';
