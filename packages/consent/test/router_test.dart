import 'dart:async';
import 'dart:io';

import 'package:genesis_consent/genesis_consent.dart';
import 'package:genesis_dialogue/genesis_dialogue.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_taxonomy/genesis_taxonomy.dart';
import 'package:test/test.dart';

import 'src/consent_fixture.g.dart';
import 'src/consent_fixtures.dart';

// --- emissions -------------------------------------------------------------

/// v1 surface: root node + two stateful counters (A from 0, B from 100).
Map<String, Object?> v1() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['cA', 'cB'],
      },
      {'id': 'cA', 'component': 'counter', 'label': 'cA', 'start': 0},
      {'id': 'cB', 'component': 'counter', 'label': 'cB', 'start': 100},
    ],
  },
};

/// v2 re-emission: cA removed; cB kept (keyed reconcile preserves its
/// identity AND live state). cA's element unmounts.
Map<String, Object?> v2NoA() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['cB'],
      },
      {'id': 'cB', 'component': 'counter', 'label': 'cB', 'start': 100},
    ],
  },
};

/// A DAG emission: `shared` is referenced by BOTH n1 and n2, so buildSeedTree
/// builds it twice — two mounted branches under one id (A19). Reachable from a
/// valid updateComponents message (the envelope rejects duplicate top-level
/// ids, not an id reused as a child of two parents).
Map<String, Object?> v1Dag() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'main',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'form',
        'children': ['n1', 'n2'],
      },
      {
        'id': 'n1',
        'component': 'node',
        'name': 'left',
        'children': ['shared'],
      },
      {
        'id': 'n2',
        'component': 'node',
        'name': 'right',
        'children': ['shared'],
      },
      {'id': 'shared', 'component': 'counter', 'label': 'shared', 'start': 0},
    ],
  },
};

UpdateComponents msg(Map<String, Object?> json) => parseUpdateComponents(json);

ActionEvent press(String id, {int? amount, String surfaceId = 'main'}) =>
    ActionEvent(
      name: 'press',
      surfaceId: surfaceId,
      sourceComponentId: id,
      payload: amount == null ? const {} : {'amount': amount},
    );

ActionEvent setTo(String id, Object? value, {String surfaceId = 'main'}) =>
    ActionEvent(
      name: 'set',
      surfaceId: surfaceId,
      sourceComponentId: id,
      payload: {'value': value},
    );

// --- live-tree probes ------------------------------------------------------

Branch? findByKey(Branch root, String id) {
  Branch? found;
  final target = ValueKey(id);
  void walk(Branch b) {
    if (found != null) return;
    if (b.key == target) {
      found = b;
      return;
    }
    b.visitChildren(walk);
  }

  walk(root);
  return found;
}

/// The string a counter currently renders (its built `Field`'s value).
String renderedValue(Branch root, String counterId) {
  final counter = findByKey(root, counterId)!;
  String? value;
  counter.visitChildren((child) {
    final seed = child.seed;
    if (seed is Field) value = seed.value?.toString();
  });
  return value!;
}

/// A canonical dump of config props AND live state (the rendered Field
/// values), used to assert a rejection left the tree byte-for-byte untouched.
String dumpTree(Branch root) {
  final lines = <String>[];
  void walk(Branch b, int depth) {
    final seed = b.seed;
    final extra = switch (seed) {
      Node n => 'node name=${n.name}',
      Field f => 'field name=${f.name} value=${f.value}',
      Counter c => 'counter label=${c.label} start=${c.start}',
      _ => seed.runtimeType.toString(),
    };
    lines.add('${'  ' * depth}${b.key}|$extra|mounted=${b.mounted}');
    b.visitChildren((c) => walk(c, depth + 1));
  }

  walk(root, 0);
  return lines.join('\n');
}

void main() {
  final catalog = Catalog.parse(
    File('test/src/consent_fixture.catalog.json').readAsStringSync(),
  );

  late DialogueSurface surface;
  late ConsentRouter router;

  setUp(() {
    consentFixtureBuildCounts.clear();
    surface = DialogueSurface(registry: componentRegistry);
    router = ConsentRouter(surface: surface, catalog: catalog);
  });

  group('ENFORCE — valid intent applies through the target state (D4)', () {
    test('press invalidates EXACTLY the target subtree', () {
      final root = router.mount(msg(v1()));
      consentFixtureBuildCounts.clear(); // mount built A and B once each

      final outcome = router.route(press('cA', amount: 3));

      expect(outcome, isA<Applied>());
      final applied = outcome as Applied;
      expect(applied.componentId, 'cA');
      expect(applied.change.from, 0);
      expect(applied.change.to, 3);

      // The mutation is synchronous; the rebuild drains on the next flush.
      final rebuilt = surface.owner.flush();

      // Exactly the target rebuilt: cA's builder ran again, cB's did NOT.
      expect(rebuilt.map((b) => b.key), [const ValueKey('cA')]);
      expect(consentFixtureBuildCounts['cA'], 1);
      expect(consentFixtureBuildCounts.containsKey('cB'), isFalse);

      // The rendered projection reflects the enforced value; sibling intact.
      expect(renderedValue(root, 'cA'), '3');
      expect(renderedValue(root, 'cB'), '100');

      // The harvest drains: a second flush is a no-op.
      expect(surface.owner.flush(), isEmpty);
    });

    test('press defaults amount to 1 when context omits it', () {
      final root = router.mount(msg(v1()));
      expect(router.route(press('cA')), isA<Applied>());
      surface.owner.flush();
      expect(renderedValue(root, 'cA'), '1');
    });

    test('last-write-wins: in-order overwrite, coalesced rebuild (D6)', () {
      final root = router.mount(msg(v1()));
      consentFixtureBuildCounts.clear();

      final first = router.route(setTo('cA', 5)) as Applied;
      final second = router.route(setTo('cA', 9)) as Applied;

      // Honest from/to provenance: the second write saw the first's result.
      expect((first.change.from, first.change.to), (0, 5));
      expect((second.change.from, second.change.to), (5, 9));

      // Two unflushed writes coalesce into ONE rebuild; the observer of the
      // rendered projection never sees the intermediate 5.
      final rebuilt = surface.owner.flush();
      expect(rebuilt.map((b) => b.key), [const ValueKey('cA')]);
      expect(consentFixtureBuildCounts['cA'], 1);
      expect(renderedValue(root, 'cA'), '9');
    });

    test(
      'enforce drains via onNeedsFlush microtask, no manual flush (D4)',
      () async {
        final root = router.mount(msg(v1()));
        consentFixtureBuildCounts.clear();
        // Wire the owner the way a renderer would (ADR-0005 test b2): flush on
        // the empty→non-empty edge of the dirty set.
        surface.owner.onNeedsFlush = () =>
            scheduleMicrotask(surface.owner.flush);

        expect(router.route(press('cA', amount: 4)), isA<Applied>());

        // No manual flush: enforce marked the branch dirty, which fired
        // onNeedsFlush; the scheduled microtask drains it on the same pipeline.
        await Future<void>.delayed(Duration.zero);

        expect(consentFixtureBuildCounts['cA'], 1);
        expect(renderedValue(root, 'cA'), '4');
      },
    );
  });

  group('REJECT — structured and side-effect-free (D2)', () {
    /// Asserts [act] rejects with [kind] and leaves the tree byte-for-byte
    /// untouched: identical canonical dump, zero rebuilds, empty dirty set.
    Rejected expectCleanReject(
      Branch root,
      ConsentOutcome Function() act,
      RejectionKind kind,
    ) {
      final before = dumpTree(root);
      consentFixtureBuildCounts.clear();

      final outcome = act();

      expect(outcome, isA<Rejected>());
      final rejected = outcome as Rejected;
      expect(rejected.kind, kind);
      expect(dumpTree(root), before, reason: 'tree must be untouched');
      expect(consentFixtureBuildCounts, isEmpty, reason: 'no builder ran');
      expect(surface.owner.flush(), isEmpty, reason: 'dirty set must be empty');
      return rejected;
    }

    test('unknownComponent — id never seen in any emission', () {
      final root = router.mount(msg(v1()));
      expectCleanReject(
        root,
        () => router.route(press('ghost')),
        RejectionKind.unknownComponent,
      );
    });

    test('undeclaredAction — mounted, but the type affords neither', () {
      final root = router.mount(msg(v1()));
      // The root node affords nothing; cA affords only press/set.
      final onNode = expectCleanReject(
        root,
        () => router.route(
          const ActionEvent(
            name: 'press',
            surfaceId: 'main',
            sourceComponentId: 'root',
          ),
        ),
        RejectionKind.undeclaredAction,
      );
      expect(onNode.availableActions, isEmpty);

      final onCounter = expectCleanReject(
        root,
        () => router.route(
          const ActionEvent(
            name: 'frobnicate',
            surfaceId: 'main',
            sourceComponentId: 'cA',
          ),
        ),
        RejectionKind.undeclaredAction,
      );
      expect(onCounter.availableActions, ['press', 'set']);
    });

    test('badPayload — declared action, invalid context (gate 3)', () {
      final root = router.mount(msg(v1()));

      // set requires an integer value.
      final missing = expectCleanReject(
        root,
        () => router.route(setTo('cA', null)),
        RejectionKind.badPayload,
      );
      expect(missing.payloadError, contains('value'));

      final wrongType = expectCleanReject(
        root,
        () => router.route(setTo('cA', 'not-an-int')),
        RejectionKind.badPayload,
      );
      expect(wrongType.payloadError, isNotNull);

      // press's amount, when present, must be an integer.
      expectCleanReject(
        root,
        () => router.route(
          const ActionEvent(
            name: 'press',
            surfaceId: 'main',
            sourceComponentId: 'cA',
            payload: {'amount': 'lots'},
          ),
        ),
        RejectionKind.badPayload,
      );
    });

    test('surfaceId mismatch folds into unknownComponent (single-surface)', () {
      final root = router.mount(msg(v1()));
      expectCleanReject(
        root,
        () => router.route(press('cA', surfaceId: 'other')),
        RejectionKind.unknownComponent,
      );
    });
  });

  group('STALENESS — the A8 agent-async-gap bridge (D3)', () {
    test('a re-emission that drops cA makes a prior-valid press '
        'staleUnmounted, distinct from unknownComponent', () {
      final root = router.mount(msg(v1()));

      // cA is valid in v1.
      expect(router.route(press('cA')), isA<Applied>());
      surface.owner.flush();

      // Capture cB identity + drive its live state before re-emission.
      final cbBefore = findByKey(root, 'cB')!;
      expect(router.route(setTo('cB', 7)), isA<Applied>());
      surface.owner.flush();
      expect(renderedValue(root, 'cB'), '7');

      // v2 re-emission removes cA; keyed reconcile unmounts exactly it.
      router.apply(msg(v2NoA()));

      final caAfter = findByKey(root, 'cA');
      expect(caAfter, isNull, reason: 'cA is gone from the live tree');

      // cB kept identity AND its live count across the re-emission.
      final cbAfter = findByKey(root, 'cB')!;
      expect(identical(cbAfter, cbBefore), isTrue);
      expect(renderedValue(root, 'cB'), '7');

      // The previously-valid press now rejects as staleUnmounted — the
      // projection moved under the actor.
      final stale = router.route(press('cA'));
      expect(stale, isA<Rejected>());
      expect((stale as Rejected).kind, RejectionKind.staleUnmounted);

      // ...and that is distinguishable from a never-seen id.
      final unknown = router.route(press('ghost')) as Rejected;
      expect(unknown.kind, RejectionKind.unknownComponent);

      // The surviving cB still enforces normally.
      expect(router.route(press('cB', amount: 3)), isA<Applied>());
      surface.owner.flush();
      expect(renderedValue(root, 'cB'), '10');
    });
  });

  group('lifecycle + wire interop', () {
    test('route before mount throws', () {
      expect(() => router.route(press('cA')), throwsStateError);
    });

    test('a DAG-shared id resolves to >1 mounted branch and route throws '
        'rather than silently mutating one copy', () {
      // mount succeeds — taxonomy/dialogue permit the DAG share (built twice).
      final root = router.mount(msg(v1Dag()));
      expect(findByKey(root, 'shared'), isNotNull);

      // ...but enforcement against the ambiguous id is refused loudly.
      expect(
        () => router.route(press('shared')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('resolves to 2 mounted branches'),
          ),
        ),
      );
    });

    test('an a2ui_core-shaped action JSON round-trips through the wire '
        'and enforces (register A27 interop)', () {
      // The exact shape a2ui_core A2uiClientAction.toJson() produces: a bare
      // action object with name/surfaceId/sourceComponentId/timestamp/context.
      // dialogue parses it; consent routes it — no a2ui_core dependency.
      final root = router.mount(msg(v1()));
      final wire = <String, Object?>{
        'name': 'set',
        'surfaceId': 'main',
        'sourceComponentId': 'cA',
        'timestamp': '2026-06-14T10:00:00.000Z',
        'context': {'value': 42},
      };

      final event = parseActionEvent(wire);
      final outcome = router.route(event);

      expect(outcome, isA<Applied>());
      expect((outcome as Applied).change.to, 42);
      surface.owner.flush();
      expect(renderedValue(root, 'cA'), '42');
    });
  });
}
