import 'package:flutter_test/flutter_test.dart';

import 'fixtures/constellation_arrange_harness.dart';

/// «Reset positions» saves the layout it clears in the same server call, and
/// one Undo / Redo puts every anchor back / clears them again through a
/// snapshot restore, never through per-anchor writes.

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ArrangeHarness harness;

  setUp(() async {
    harness = await arrangeHarness();
    await _drain();
  });

  group('undoable reset', () {
    test('a reset that saves history is one server call that asks for the '
        'history snapshot', () async {
      await harness.placement.resetAll(saveHistory: true);

      expect(harness.anchors.resets, hasLength(1));
      expect(harness.anchors.resets.single.saveHistory, isTrue);
      expect(harness.anchors.anchors, isEmpty);
      expect(harness.anchors.applies, isEmpty);
    });

    test(
      'a plain reset keeps asking for no snapshot and is not undoable',
      () async {
        await harness.placement.resetAll();

        expect(harness.anchors.resets.single.saveHistory, isFalse);
        expect(harness.placement.history.canUndo, isFalse);
      },
    );

    test('a reset that saves history records one undoable entry', () async {
      await harness.placement.resetAll(saveHistory: true);

      expect(harness.placement.history.length, 1);
      expect(harness.placement.history.canUndo, isTrue);
      expect(harness.placement.history.canRedo, isFalse);
    });

    test('one undo restores every anchor from the reset snapshot', () async {
      final before = {...harness.anchors.anchors};
      expect(before, hasLength(3));
      await harness.placement.resetAll(saveHistory: true);
      expect(harness.anchors.anchors, isEmpty);

      final undone = await harness.placement.undo();

      expect(undone, isTrue);
      expect(harness.anchors.restores, hasLength(1));
      expect(harness.anchors.anchors, before);
      expect(
        harness.anchors.applies,
        isEmpty,
        reason: 'the anchors come back in one restore, not one write each',
      );
      expect(harness.placement.history.canRedo, isTrue);
    });

    test('redo of an undone reset restores the snapshot written by the '
        'undo and so clears every anchor again', () async {
      await harness.placement.resetAll(saveHistory: true);
      await harness.placement.undo();

      final redone = await harness.placement.redo();

      expect(redone, isTrue);
      expect(harness.anchors.restores, hasLength(2));
      expect(harness.anchors.anchors, isEmpty);
      expect(harness.placement.history.canUndo, isTrue);
    });

    test(
      'a drag made after the reset clears the redo of an undone reset',
      () async {
        await harness.placement.resetAll(saveHistory: true);
        await harness.placement.undo();
        expect(harness.placement.history.canRedo, isTrue);

        harness.placement.place(
          parent: arrangePersonOne,
          position: arrangePosition(9, 9),
          companions: const [],
        );
        await _drain();

        expect(harness.placement.history.canRedo, isFalse);
      },
    );

    test('a reset after a drag is undone before the drag is', () async {
      harness.placement.place(
        parent: arrangePersonOne,
        position: arrangePosition(9, 9),
        companions: const [],
      );
      await _drain();
      await harness.placement.resetAll(saveHistory: true);
      expect(harness.placement.history.length, 2);

      await harness.placement.undo();

      expect(harness.anchors.restores, hasLength(1));
      expect(harness.anchors.anchors[arrangePersonOne], arrangePosition(9, 9));
      expect(harness.anchors.anchors, hasLength(3));
    });

    test('a reset the server keeps refusing leaves nothing to undo', () async {
      harness.anchors.resetError = StateError('server down');

      await expectLater(
        harness.placement.resetAll(saveHistory: true),
        throwsStateError,
      );

      expect(harness.placement.history.canUndo, isFalse);
      expect(harness.anchors.anchors, hasLength(3));
    });
  });
}
