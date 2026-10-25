import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_layout_history_sheet.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_layout_history_harness.dart';

Map<String, Offset?> _positions(ConstellationCubit cubit) => {
  for (final id in ['p1', 'p2', 'p3', 'p4'])
    id: cubit.graphController.getPositionOrNullForId('fp:$id'),
};

/// The sheet promises painted, tappable thumbnails. Select them in their
/// visible order without prescribing row keys, row widget classes or date copy.
Finder _thumbnails() => find.byElementPredicate(
  (element) {
    final widget = element.widget;
    return widget is CustomPaint &&
        element.findAncestorWidgetOfExactType<ConstellationLayoutThumbnail>() !=
            null &&
        (widget.painter != null || widget.foregroundPainter != null) &&
        ModalRoute.of(element)?.isCurrent == true;
  },
);

Finder _thumbnailAt(WidgetTester tester, int index) {
  final elements = _thumbnails().evaluate().toList()
    ..sort((a, b) {
      final at = tester.getTopLeft(
        find.byElementPredicate((e) => identical(e, a)),
      );
      final bt = tester.getTopLeft(
        find.byElementPredicate((e) => identical(e, b)),
      );
      final vertical = at.dy.compareTo(bt.dy);
      return vertical != 0 ? vertical : at.dx.compareTo(bt.dx);
    });
  expect(elements.length, greaterThan(index));
  return find.byElementPredicate((e) => identical(e, elements[index]));
}

Finder _thumbnailFor(
  WidgetTester tester,
  LayoutHistoryServer server,
  LayoutHistorySnapshot snapshot,
) {
  final ordered = [...server.snapshots]
    ..sort((a, b) {
      final kind = a.kind.compareTo(b.kind);
      return kind != 0 ? kind : b.createdAt.compareTo(a.createdAt);
    });
  expect(_thumbnails(), findsNWidgets(ordered.length));
  return _thumbnailAt(tester, ordered.indexOf(snapshot));
}

/// Widget actions can leave a refresh in the fake-async zone. Keep pumping
/// while awaiting a subsequent action that may share that in-flight refresh.
Future<T?> _runWithPumps<T>(
  WidgetTester tester,
  Future<T> Function() action,
) => tester.runAsync(() async {
  var completed = false;
  final result = action().whenComplete(() => completed = true);
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.pumpAndSettle();
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    completed,
    isTrue,
    reason: 'the action completes while frames are pumped',
  );
  return result;
});

Future<void> _tap(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(
    action,
    findsOneWidget,
    reason: 'the visible $label action is reachable',
  );
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _arrange(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Arrange'));
  await tester.pumpAndSettle();
  await _tap(tester, action);
}

/// Keep the actual Field, camera controls and selection bar mounted so layout
/// changes, including preview and Tidy offsets, reach the rendered positions.
Future<ConstellationSelectionCubit> _mount(
  WidgetTester tester,
  LayoutHistoryHarness h,
) async {
  final selection = ConstellationSelectionCubit();
  addTearDown(selection.close);
  await pumpArrangeBody(
    tester,
    h.cubit,
    arrangeV2Enabled: true,
    selection: selection,
  );
  await tester.pumpAndSettle();
  return selection;
}

/// A prior layout from a different session: free people overlap and are far
/// from their canonical directions. Pinned people retain their real positions.
class _OverlappingFreePeople implements SceneLayoutAlgorithm {
  _OverlappingFreePeople(this.before);
  final Map<String, Offset?> before;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final ego = Offset(
      request.canvasSize.width / 2,
      request.canvasSize.height / 2,
    );
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      isTerminal: true,
      positions: {
        for (final id in request.nodeIds)
          id: switch (id) {
            'fp:p3' => ScenePoint(x: ego.dx - 10, y: ego.dy - 340),
            'fp:p4' => ScenePoint(x: ego.dx + 10, y: ego.dy - 340),
            _ => ScenePoint(
              x: before[id.replaceFirst('fp:', '')]?.dx ?? ego.dx,
              y: before[id.replaceFirst('fp:', '')]?.dy ?? ego.dy,
            ),
          },
      },
    );
  }
}

void _expectSamePositions(
  Map<String, Offset?> actual,
  Map<String, Offset?> expected,
) {
  expect(actual.keys, unorderedEquals(expected.keys));
  for (final id in expected.keys) {
    expect(actual[id], isNotNull, reason: '$id remains on the Field');
    expect(expected[id], isNotNull, reason: '$id has a reference position');
    expect(actual[id]!.dx, closeTo(expected[id]!.dx, 0.01), reason: '$id x');
    expect(actual[id]!.dy, closeTo(expected[id]!.dy, 0.01), reason: '$id y');
  }
}

void _expectAnchorsAtPositions(
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> anchors,
  Map<String, Offset?> positions,
) {
  for (final entry in anchors.entries) {
    final point = constellationV1AnchorToPoint(entry.value);
    final position = positions[entry.key.id]!;
    expect(point.x, closeTo(position.dx, 0.01), reason: '${entry.key.id} x');
    expect(point.y, closeTo(position.dy, 0.01), reason: '${entry.key.id} y');
  }
}

void main() {
  group('layout history sheet', () {
    for (final (index, description) in [
      (0, 'puts the favourite thumbnail above every history layout'),
      (1, 'puts the newest history thumbnail directly below the favourite'),
      (2, 'puts the oldest history thumbnail last'),
    ]) {
      testWidgets(description, (tester) async {
        final server = LayoutHistoryServer();
        final old = server.seed(
          kind: 1,
          createdAt: DateTime.utc(2026, 10, 23),
          at: {arrangePersonOne: arrangePosition(4, 2)},
        );
        final favourite = server.seed(
          kind: 0,
          createdAt: DateTime.utc(2026, 10, 22),
          at: server.anchors,
        );
        final newest = server.seed(
          kind: 1,
          createdAt: DateTime.utc(2026, 10, 25),
          at: {},
        );
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        await _mount(tester, h);

        await _arrange(tester, 'Layout history');

        expect(
          _thumbnails(),
          findsNWidgets(3),
          reason: 'every saved layout has a thumbnail, including the empty one',
        );
        expect(
          server.events,
          isEmpty,
          reason: 'opening history writes nothing',
        );
        await tester.tap(_thumbnailAt(tester, index));
        await tester.pumpAndSettle();
        expect(
          server.events,
          isEmpty,
          reason: 'selecting a thumbnail only previews',
        );
        await _tap(tester, 'Restore this');

        final selected = [favourite, newest, old][index];
        expect(server.events, ['save:1:1', 'restore:${selected.id}']);
        expect(
          server.anchors,
          selected.anchors,
          reason:
              'the visible thumbnail selects the layout in the promised order',
        );
      });
    }

    testWidgets(
      'tapping a history layout previews without writes, then '
      'Restore this saves the replaced layout once and is undone in one step',
      (tester) async {
        final server = LayoutHistoryServer();
        final source = server.seed(
          kind: 1,
          createdAt: DateTime.utc(2026, 10, 24),
          at: {
            arrangePersonOne: arrangePosition(-5, -2),
          },
        );
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        await _mount(tester, h);
        // Make the committed layout newer than both the saved source and the
        // initial fetch, so a stale pre-restore snapshot is distinguishable.
        h.placement.place(
          parent: arrangePersonOne,
          position: arrangePosition(7, 2),
          companions: const [],
        );
        await tester.pumpAndSettle();
        expect(server.anchors[arrangePersonOne]!.xUnits, closeTo(7, 1e-6));
        // The fake server does not publish realtime invalidations. Refresh
        // explicitly to display the acknowledged layout before previewing it.
        await _runWithPumps(tester, h.cubit.load);
        await tester.pumpAndSettle();
        final before = Map.of(server.anchors);
        final beforePositions = _positions(h.cubit);
        _expectAnchorsAtPositions(before, beforePositions);
        final existingSnapshotIds = server.snapshots.map((s) => s.id).toSet();
        final eventsBeforePreview = List.of(server.events);
        final undoStepsBeforeRestore = h.placement.history.length;
        await _arrange(tester, 'Layout history');

        await tester.tap(_thumbnailFor(tester, server, source));
        await tester.pumpAndSettle();
        final previewPositions = _positions(h.cubit);
        expect(previewPositions, isNot(beforePositions));
        expect(server.events, eventsBeforePreview);
        expect(server.anchors, before);

        final anchorsAtSave =
            <Map<ConstellationAnchorTarget, ConstellationAnchorPosition>>[];
        List<LayoutHistorySnapshot>? snapshotsAtRestore;
        List<String>? eventsAtRestore;
        Map<ConstellationAnchorTarget, ConstellationAnchorPosition>?
        anchorsAtRestore;
        server.onSave = () {
          anchorsAtSave.add(Map.of(server.anchors));
        };
        server.onRestore = (snapshotId) {
          expect(snapshotId, source.id);
          snapshotsAtRestore = server.snapshots
              .where((s) => !existingSnapshotIds.contains(s.id))
              .toList();
          eventsAtRestore = server.events
              .skip(eventsBeforePreview.length)
              .toList();
          anchorsAtRestore = Map.of(server.anchors);
        };

        await _tap(tester, 'Restore this');

        expect(
          anchorsAtSave,
          hasLength(1),
          reason: 'restoring a history layout saves exactly once',
        );
        expect(anchorsAtSave.single, before);
        expect(eventsAtRestore, [
          'save:1:1',
        ], reason: 'the save has completed before the restore mutates anchors');
        expect(anchorsAtRestore, before);
        expect(snapshotsAtRestore, hasLength(1));
        final saved = snapshotsAtRestore!.single;
        expect(saved.kind, 1);
        expect(saved.reason, 1);
        expect(saved.anchors, before);
        // Snapshot anchor coordinates must describe the latest committed
        // positions, rather than the older source or its displayed preview.
        _expectAnchorsAtPositions(saved.anchors, beforePositions);
        expect(server.events.skip(eventsBeforePreview.length), [
          'save:1:1',
          'restore:${source.id}',
        ]);
        expect(
          server.snapshots.where((s) => !existingSnapshotIds.contains(s.id)),
          hasLength(1),
        );
        expect(server.anchors, source.anchors);
        _expectSamePositions(_positions(h.cubit), previewPositions);
        expect(h.placement.history.length, undoStepsBeforeRestore + 1);
        server.onSave = null;
        server.onRestore = null;
        expect(
          await _runWithPumps(tester, h.cubit.undoArrangement),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(server.anchors, before);
        expect(
          h.placement.history.length,
          undoStepsBeforeRestore,
          reason: 'one Undo consumes only the restore step',
        );
      },
    );

    testWidgets('cancelling a layout preview restores every composed position '
        'without changing pins or history', (tester) async {
      final server = LayoutHistoryServer();
      final source = server.seed(
        kind: 1,
        createdAt: DateTime.utc(2026, 10, 24),
        at: {arrangePersonOne: arrangePosition(-5, -2)},
      );
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await _mount(tester, h);
      final before = _positions(h.cubit);
      final pins = Map.of(server.anchors);

      await _arrange(tester, 'Layout history');
      await tester.tap(_thumbnailFor(tester, server, source));
      await tester.pumpAndSettle();
      expect(_positions(h.cubit), isNot(before));
      await _tap(tester, 'Cancel');

      _expectSamePositions(_positions(h.cubit), before);
      expect(server.anchors, pins);
      expect(server.events, isEmpty);
      expect(h.cubit.canUndoArrangement, isFalse);
    });
  });

  group('favourite layout', () {
    testWidgets(
      'Save as favourite replaces the favourite and one Undo restores '
      'the previous favourite without moving the current Field',
      (tester) async {
        final server = LayoutHistoryServer();
        final previous = server.seed(
          kind: 0,
          createdAt: DateTime.utc(2026, 10, 24),
          at: {arrangePersonOne: arrangePosition(-5, -2)},
        );
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        await _mount(tester, h);
        final current = Map.of(server.anchors);
        final positions = _positions(h.cubit);

        await _arrange(tester, 'Save as favourite');

        expect(server.favourite!.anchors, current);
        expect(server.snapshots.where((s) => s.kind == 0), hasLength(1));
        expect(h.cubit.canUndoArrangement, isTrue);
        _expectSamePositions(_positions(h.cubit), positions);
        expect(
          await _runWithPumps(tester, h.cubit.undoArrangement),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(server.favourite!.anchors, previous.anchors);
        expect(server.anchors, current);
        _expectSamePositions(_positions(h.cubit), positions);
        expect(
          h.cubit.canUndoArrangement,
          isFalse,
          reason: 'saving a favourite is one undo step',
        );
      },
    );

    testWidgets('Restore favourite writes one pre-restore snapshot and '
        'does not duplicate the snapshot saved by the restore endpoint', (
      tester,
    ) async {
      final server = LayoutHistoryServer();
      final favourite = server.seed(
        kind: 0,
        createdAt: DateTime.utc(2026, 10, 24),
        at: {arrangePersonOne: arrangePosition(-5, -2)},
      );
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await _mount(tester, h);
      final before = Map.of(server.anchors);

      await _arrange(tester, 'Restore favourite');

      expect(server.events, ['save:1:1', 'restore:${favourite.id}']);
      expect(server.snapshots.where((s) => s.kind == 1), hasLength(1));
      expect(server.snapshots.last.anchors, before);
      expect(server.anchors, favourite.anchors);
      expect(
        await _runWithPumps(tester, h.cubit.undoArrangement),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(server.anchors, before);
    });
  });

  group('layout restoration across devices', () {
    for (final kind in [0, 1]) {
      testWidgets(
        'preview then Restore this for a ${kind == 0 ? 'favourite' : 'history'} '
        'snapshot on a second device clears prior hints and Tidy offsets '
        'and reproduces the first device positions',
        (tester) async {
          final server = LayoutHistoryServer();
          final first = (await tester.runAsync(
            () => layoutHistoryHarness(server),
          ))!;
          await _mount(tester, first);
          if (kind == 0) await _arrange(tester, 'Save as favourite');
          final source = kind == 0
              ? server.favourite!
              : server.seed(
                  kind: 1,
                  createdAt: DateTime.utc(2026, 10, 24),
                  at: server.anchors,
                );
          final expected = _positions(first.cubit);
          expect(expected.values, everyElement(isNotNull));

          final second = (await tester.runAsync(
            () => layoutHistoryHarness(server),
          ))!;
          await _mount(tester, second);
          second.cubit.requestConstellationLayoutForTest(
            algorithm: _OverlappingFreePeople(_positions(second.cubit)),
          );
          await tester.pumpAndSettle();
          final priorPositions = _positions(second.cubit);
          expect(
            priorPositions,
            isNot(expected),
            reason: 'the second session has different priors',
          );
          await _arrange(tester, 'Tidy up');
          final tidied = _positions(second.cubit);
          expect(
            tidied,
            isNot(priorPositions),
            reason: 'the second session has Tidy offsets',
          );
          expect(server.anchors.keys.toSet(), {
            arrangePersonOne,
            arrangePersonTwo,
          }, reason: 'Tidy leaves the free people unpinned');
          final eventsBeforePreview = List.of(server.events);
          final historyBefore = server.snapshots
              .where((s) => s.kind == 1)
              .length;

          await _arrange(tester, 'Layout history');
          await tester.tap(_thumbnailFor(tester, server, source));
          await tester.pumpAndSettle();

          _expectSamePositions(_positions(second.cubit), expected);
          expect(
            server.events,
            eventsBeforePreview,
            reason: 'preview is read only',
          );
          await _tap(tester, 'Restore this');
          _expectSamePositions(_positions(second.cubit), expected);
          expect(server.events.skip(eventsBeforePreview.length), [
            'save:1:1',
            'restore:${source.id}',
          ]);
          expect(server.anchors, source.anchors);
          expect(
            server.snapshots.where((s) => s.kind == 1),
            hasLength(historyBefore + 1),
          );
          // A later ordinary refresh must not reapply the old local Tidy layer.
          await _runWithPumps(tester, second.cubit.load);
          await tester.pumpAndSettle();
          _expectSamePositions(_positions(second.cubit), expected);
        },
      );
    }
  });

  group('automatic history for local and selection actions', () {
    testWidgets(
      'Tidy up saves exactly one snapshot before applying local offsets',
      (tester) async {
        final server = LayoutHistoryServer();
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        await _mount(tester, h);
        h.cubit.requestConstellationLayoutForTest(
          algorithm: _OverlappingFreePeople(_positions(h.cubit)),
        );
        await tester.pumpAndSettle();
        final before = _positions(h.cubit);
        final anchors = Map.of(server.anchors);
        Map<String, Offset?>? atSave;
        server.onSave = () => atSave = _positions(h.cubit);

        await _arrange(tester, 'Tidy up');

        expect(server.snapshots, hasLength(1));
        expect(server.snapshots.single.kind, 1);
        expect(server.snapshots.single.anchors, anchors);
        expect(atSave, before);
        expect(_positions(h.cubit), isNot(before));
        expect(server.batches, isEmpty);
        expect(server.anchors, anchors);
      },
    );

    testWidgets('Gather saves one snapshot before pinning the selection in one '
        'batch', (tester) async {
      final server = LayoutHistoryServer();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      final selection = await _mount(tester, h);
      final p3 = ConstellationAnchorTarget.person('p3');
      final p4 = ConstellationAnchorTarget.person('p4');
      selection.addAll([p3, p4]);
      await tester.pumpAndSettle();
      final anchors = Map.of(server.anchors);
      final before = _positions(h.cubit);
      Map<String, Offset?>? atSave;
      server.onSave = () => atSave = _positions(h.cubit);

      await _tap(tester, 'Gather');

      expect(server.snapshots, hasLength(1));
      expect(server.snapshots.single.kind, 1);
      expect(server.snapshots.single.anchors, anchors);
      expect(atSave, before);
      expect(server.events.first, startsWith('save:1:'));
      expect(server.events.last, 'apply');
      expect(server.batches, hasLength(1));
      expect(server.batches.single.map((op) => op['targetId']).toSet(), {
        'p3',
        'p4',
      });
      expect(server.anchors.keys.toSet(), {...anchors.keys, p3, p4});
    });
  });
}
