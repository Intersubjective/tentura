import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_action.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_offset_layer.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_up.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_arrangement_history.dart';

import '../fixtures/constellation_tidy_overlap.dart';

/// «Tidy up» is one undoable arrangement step; its tidied positions live in a
/// post-layout offset layer, so they survive the layout re-running on a data
/// refresh and go away with Undo.

const _radius = 20.0;

ConstellationTidyNode _node(String id, LPoint at, {bool pinned = false}) => (
  id: id,
  position: at,
  radius: _radius,
  labelSize: (w: 36, h: 12),
  pinned: pinned,
);

/// The layout's own positions: three people 10 px apart, one far off.
Map<String, LPoint> _layoutPositions() => {
  'A': (x: -10, y: -340),
  'B': (x: 0, y: -340),
  'C': (x: 10, y: -340),
  'Far': (x: 0, y: 340),
};

({
  ConstellationArrangementHistory history,
  ConstellationTidyOffsetLayer layer,
  ConstellationTidyAction action,
})
_setup() {
  final layer = ConstellationTidyOffsetLayer();
  final history = ConstellationArrangementHistory(
    applyOps: (_) async => true,
    restoreSnapshot: (_) async => null,
    applyLocalLayout: (_) async {},
    flushPlacementOutbox: () async {},
    saveSnapshot: (_) async => 'S',
    newOpId: () => 'op',
    applyTidyOffsets: (offsets) async => layer.replaceAll(offsets),
  );
  return (
    history: history,
    layer: layer,
    action: ConstellationTidyAction(layer: layer, history: history),
  );
}

ConstellationTidyOutcome? _tidy(ConstellationTidyAction action) => action.tidy(
  ego: (x: 0, y: 0),
  nodes: [
    for (final e in _layoutPositions().entries) _node(e.key, e.value),
  ],
);

void main() {
  group('tidy offset history entry', () {
    test(
      'undo restores the offsets from before and redo the ones after',
      () async {
        final applied = <Map<String, LPoint>>[];
        final history =
            ConstellationArrangementHistory(
              applyOps: (_) async => true,
              restoreSnapshot: (_) async => null,
              applyLocalLayout: (_) async {},
              flushPlacementOutbox: () async {},
              saveSnapshot: (_) async => 'S',
              newOpId: () => 'op',
              applyTidyOffsets: (offsets) async => applied.add(offsets),
            )..record(
              const TidyOffsetEntry(
                before: {},
                after: {'A': (x: 5.0, y: 0.0)},
              ),
            );

        expect(history.length, 1);
        expect(await history.undo(), isTrue);
        expect(applied.single, isEmpty);

        expect(await history.redo(), isTrue);
        expect(applied.last, {'A': (x: 5.0, y: 0.0)});
      },
    );
  });

  group('tidy up action', () {
    test('records exactly one undo entry', () {
      final s = _setup();

      final outcome = _tidy(s.action);

      expect(outcome, isNotNull);
      expect(s.history.length, 1);
      expect(s.history.canUndo, isTrue);
    });

    test('reports the people the pure tidy up displaces, counted', () {
      final s = _setup();
      final nodes = [
        for (final e in _layoutPositions().entries) _node(e.key, e.value),
      ];
      final pure = constellationTidyUp(ego: (x: 0, y: 0), nodes: nodes);

      final outcome = _tidy(s.action)!;

      expect(outcome.movedCount, pure.movedCount);
      expect(outcome.movedCount, pure.moves.length);
      expect(outcome.movedCount, greaterThan(0));
      final afterRefresh = s.layer.apply(_layoutPositions());
      final displaced = {
        for (final e in _layoutPositions().entries)
          if (afterRefresh[e.key] != e.value) e.key,
      };
      expect(displaced, pure.moves.keys.toSet());
    });

    test('records nothing when nobody overlaps', () {
      final s = _setup();

      final outcome = s.action.tidy(
        ego: (x: 0, y: 0),
        nodes: [
          _node('A', (x: 340, y: 0)),
          _node('B', (x: -340, y: 0)),
        ],
      );

      expect(outcome, isNull);
      expect(s.history.canUndo, isFalse);
    });

    test('a layout re-run after a data refresh keeps the tidied positions', () {
      final s = _setup();
      _tidy(s.action);

      // The refresh re-runs the layout, which puts people back at its own
      // positions; the offset layer is applied after it.
      final refreshed = s.layer.apply(_layoutPositions());

      expect(
        tidyOverlaps(refreshed, radius: _radius, labelSize: (w: 36, h: 12)),
        isEmpty,
      );
      expect(refreshed['Far'], _layoutPositions()['Far']);
    });

    test('undo puts the layout positions back', () async {
      final s = _setup();
      _tidy(s.action);

      expect(await s.history.undo(), isTrue);

      expect(s.layer.apply(_layoutPositions()), _layoutPositions());
      expect(s.layer.isEmpty, isTrue);
    });

    test('redo tidies again', () async {
      final s = _setup();
      _tidy(s.action);
      final tidied = s.layer.apply(_layoutPositions());
      await s.history.undo();

      expect(await s.history.redo(), isTrue);

      expect(s.layer.apply(_layoutPositions()), tidied);
    });
  });
}
