import 'package:genesis_console/genesis_console.dart';
import 'package:test/test.dart';

void main() {
  late _RecordingSink sink;
  late Console console;

  // A counters surface: screen -> box -> [c1=0, c2=10, hint].
  Object counters() => {
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': 'console',
      'components': [
        {
          'id': 'root',
          'component': 'screen',
          'children': ['panel'],
        },
        {
          'id': 'panel',
          'component': 'box',
          'title': 'Counters',
          'children': ['c1', 'c2', 'hint'],
        },
        {'id': 'c1', 'component': 'counter', 'label': 'Apples', 'start': 0},
        {'id': 'c2', 'component': 'counter', 'label': 'Oranges', 'start': 10},
        {'id': 'hint', 'component': 'text', 'content': 'press a counter'},
      ],
    },
  };

  // Reconciled surface: c1 dropped, c2 kept.
  Object countersV2() => {
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': 'console',
      'components': [
        {
          'id': 'root',
          'component': 'screen',
          'children': ['panel'],
        },
        {
          'id': 'panel',
          'component': 'box',
          'title': 'Counters',
          'children': ['c2', 'hint'],
        },
        {'id': 'c2', 'component': 'counter', 'label': 'Oranges', 'start': 10},
        {'id': 'hint', 'component': 'text', 'content': 'c1 removed'},
      ],
    },
  };

  ActionEvent press(String id, [int? amount]) => ActionEvent(
    name: 'press',
    surfaceId: console.surfaceId!,
    sourceComponentId: id,
    payload: {if (amount != null) 'amount': amount},
  );

  ActionEvent setValue(String id, Object? value) => ActionEvent(
    name: 'set',
    surfaceId: console.surfaceId!,
    sourceComponentId: id,
    payload: {'value': value},
  );

  setUp(() async {
    sink = _RecordingSink();
    console = await Console.create(sink: sink);
  });

  test('create asserts catalog types are registry-backed; not yet mounted', () {
    // Reaching setUp without throwing means the catalog ⊆ registry check held.
    expect(console.surfaceId, isNull);
  });

  test('mount paints frame 0 with both counters and the box title', () async {
    await console.loadOrApply(counters());
    expect(sink.frames, greaterThan(0));
    expect(console.surfaceId, 'console');
    final grid = console.snapshot();
    expect(grid, contains('Apples: 0'));
    expect(grid, contains('Oranges: 10'));
    expect(grid, contains('Counters'));
  });

  test('a valid press is Applied and re-renders the new value', () async {
    await console.loadOrApply(counters());
    final outcome = await console.route(press('c1'));
    expect(outcome, isA<Applied>());
    final applied = outcome as Applied;
    expect(applied.change.from, 0);
    expect(applied.change.to, 1);
    final grid = console.snapshot();
    expect(grid, contains('Apples: 1'));
    expect(grid, contains('Oranges: 10'), reason: 'sibling untouched');
  });

  test('counters route independently; press accepts an amount', () async {
    await console.loadOrApply(counters());
    await console.route(press('c1'));
    final outcome = await console.route(press('c2', 5));
    expect((outcome as Applied).change.to, 15);
    final grid = console.snapshot();
    expect(grid, contains('Apples: 1'));
    expect(grid, contains('Oranges: 15'));
  });

  test('a set with a valid integer Applies', () async {
    await console.loadOrApply(counters());
    final outcome = await console.route(setValue('c1', 42));
    expect(outcome, isA<Applied>());
    expect(console.snapshot(), contains('Apples: 42'));
  });

  test(
    'a badPayload set is Rejected; surface and frame count untouched',
    () async {
      await console.loadOrApply(counters());
      await console.route(press('c1')); // Apples -> 1
      final framesBefore = sink.frames;
      final flushesBefore = console.flushCount;
      final outcome = await console.route(setValue('c1', 'oops'));
      expect(outcome, isA<Rejected>());
      expect((outcome as Rejected).kind, RejectionKind.badPayload);
      expect(console.snapshot(), contains('Apples: 1'), reason: 'no mutation');
      expect(sink.frames, framesBefore, reason: 'no new frame emitted');
      // The byte-counting sink skips an empty-diff frame, so also assert NO
      // render pass ran at all — a rejection must not rebuild the tree.
      expect(
        console.flushCount,
        flushesBefore,
        reason: 'a rejection triggers no render pass',
      );
    },
  );

  test('an action on an unknown id is Rejected unknownComponent', () async {
    await console.loadOrApply(counters());
    final outcome = await console.route(press('nope'));
    expect((outcome as Rejected).kind, RejectionKind.unknownComponent);
  });

  test(
    'an action a component does not afford is Rejected undeclaredAction',
    () async {
      await console.loadOrApply(counters());
      // 'panel' is a mounted box, but its catalog type declares no actions.
      final outcome = await console.route(press('panel'));
      expect((outcome as Rejected).kind, RejectionKind.undeclaredAction);
    },
  );

  test('a press with a non-integer amount is Rejected badPayload', () async {
    await console.loadOrApply(counters());
    // The REPL forwards an unparseable amount raw rather than defaulting to +1,
    // so a non-integer amount is rejected instead of silently incrementing.
    final outcome = await console.route(
      ActionEvent(
        name: 'press',
        surfaceId: console.surfaceId!,
        sourceComponentId: 'c1',
        payload: {'amount': 'abc'},
      ),
    );
    expect((outcome as Rejected).kind, RejectionKind.badPayload);
    expect(console.snapshot(), contains('Apples: 0'), reason: 'no mutation');
  });

  test(
    'dropping a component makes its action staleUnmounted; siblings live',
    () async {
      await console.loadOrApply(counters());
      await console.loadOrApply(countersV2()); // drops c1, keeps c2
      final stale = await console.route(press('c1'));
      expect((stale as Rejected).kind, RejectionKind.staleUnmounted);
      final live = await console.route(press('c2'));
      expect(live, isA<Applied>());
    },
  );

  test('reconcile preserves a counter live count across an apply', () async {
    await console.loadOrApply(counters());
    await console.route(press('c2', 5)); // Oranges -> 15
    await console.loadOrApply(countersV2()); // drops c1, keeps c2
    final grid = console.snapshot();
    expect(
      grid,
      contains('Oranges: 15'),
      reason: 'live state survives reconcile, not reset to seed start',
    );
    // Prove the apply actually took effect — otherwise the count above would
    // also pass for a no-op apply: the new hint rendered and c1 is gone.
    expect(grid, contains('c1 removed'), reason: 'apply re-rendered the hint');
    expect(grid, isNot(contains('Apples')), reason: 'the apply dropped c1');
  });

  test(
    'the render root type is fixed: a root-type change is rejected',
    () async {
      await console.loadOrApply(counters());
      final badRoot = {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 'console',
          'components': [
            {'id': 'root', 'component': 'box', 'title': 'nope'},
          ],
        },
      };
      await expectLater(console.loadOrApply(badRoot), throwsArgumentError);
    },
  );
}

/// Counts emitted (non-empty) frames; the console's surface paints into it.
class _RecordingSink implements Sink<List<int>> {
  int frames = 0;

  @override
  void add(List<int> data) => frames++;

  @override
  void close() {}
}
