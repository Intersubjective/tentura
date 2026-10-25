import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_layout_history_harness.dart';

Future<void> _drain() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Offset?> _positions(ConstellationCubit cubit) => {
  for (final id in ['p1', 'p2', 'p3', 'p4'])
    id: cubit.graphController.getPositionOrNullForId('fp:$id'),
};

void _drag(LayoutHistoryHarness h, double x) => h.placement.place(
  parent: arrangePersonOne,
  position: arrangePosition(x, 2),
  companions: const [],
);

void main() {
  group('automatic history before bulk arrangement', () {
    testWidgets('Rearrange saves the current layout exactly once before '
        'changing composed positions', (tester) async {
      final server = LayoutHistoryServer();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await pumpArrangeBody(tester, h.cubit, arrangeV2Enabled: true);
      final before = _positions(h.cubit);
      final anchors = Map.of(server.anchors);
      Map<String, Offset?>? positionsAtSave;
      server.onSave = () => positionsAtSave = _positions(h.cubit);

      h.cubit.rearrangeFreeNodes();
      await tester.pumpAndSettle();

      expect(server.snapshots, hasLength(1));
      expect(server.snapshots.single.kind, 1);
      expect(server.snapshots.single.reason, 3); // rebuild
      expect(server.snapshots.single.anchors, anchors);
      expect(positionsAtSave, before);
      expect(
        server.batches,
        isEmpty,
        reason: 'Rearrange leaves free people free',
      );
    });

    testWidgets('Arrange in sector saves one snapshot before the single '
        'placement batch and before optimistic movement', (tester) async {
      final server = LayoutHistoryServer();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await pumpArrangeBody(tester, h.cubit, arrangeV2Enabled: true);
      final anchors = Map.of(server.anchors);
      final before = _positions(h.cubit);
      Map<String, Offset?>? positionsAtSave;
      server.onSave = () => positionsAtSave = _positions(h.cubit);

      expect(
        h.cubit.placeArrangement({
          arrangePersonOne: const Offset(3300, 3100),
          arrangePersonTwo: const Offset(3400, 3200),
        }),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(server.snapshots, hasLength(1));
      expect(server.snapshots.single.kind, 1);
      expect(server.snapshots.single.anchors, anchors);
      expect(server.events.first, startsWith('save:1:'));
      expect(server.events.last, 'apply');
      expect(server.batches, hasLength(1));
      expect(server.batches.single, hasLength(2));
      expect(positionsAtSave, before);
      expect(server.anchors, isNot(anchors));
    });

    testWidgets('Rearrange everyone saves history even when nobody is pinned', (
      tester,
    ) async {
      final server = LayoutHistoryServer()..anchors.clear();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await pumpArrangeBody(tester, h.cubit, arrangeV2Enabled: true);
      h.cubit.previewRearrangeAll();
      await tester.pumpAndSettle();
      expect(server.events, isEmpty, reason: 'preview is read only');

      expect(await tester.runAsync(h.cubit.applyRearrangePreview), isTrue);
      await tester.pumpAndSettle();

      expect(server.events, ['save:1:3']);
      expect(server.snapshots.single.anchors, isEmpty);
      expect(server.anchors, isEmpty);
    });

    testWidgets('successive bulk actions each save history without using the '
        'manual drag throttle', (
      tester,
    ) async {
      final server = LayoutHistoryServer();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await pumpArrangeBody(tester, h.cubit, arrangeV2Enabled: true);
      final before = Map.of(server.anchors);

      h.cubit.rearrangeFreeNodes();
      await tester.pumpAndSettle();

      expect(
        await tester.runAsync(
          () => h.cubit.resetAllPositions(saveHistory: true),
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(server.events, ['save:1:3', 'save:1:2', 'reset']);
      expect(server.snapshots, hasLength(2));
      expect(server.snapshots.map((s) => s.anchors), everyElement(before));
      expect(server.anchors, isEmpty);
    });

    testWidgets('a bulk snapshot waits for the latest drag acknowledgement', (
      tester,
    ) async {
      final server = LayoutHistoryServer();
      final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
      await pumpArrangeBody(tester, h.cubit, arrangeV2Enabled: true);
      final gate = server.applyGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      _drag(h, 7);
      await tester.pumpAndSettle();
      expect(server.batches, hasLength(1));
      // The drag may already have saved its own `manual` snapshot.
      final savedBeforeBulk = server.snapshots.length;

      h.cubit.previewRearrangeAll();
      final applied = h.cubit.applyRearrangePreview();
      await tester.pumpAndSettle();
      final whileAwaitingAck = server.snapshots.length;
      gate.complete();
      expect(await applied, isTrue);
      await tester.pumpAndSettle();

      expect(
        whileAwaitingAck,
        savedBeforeBulk,
        reason: 'history must include the pending drag once it is confirmed',
      );
      final bulk = server.snapshots.where((s) => s.reason == 3).toList();
      expect(bulk, hasLength(1));
      expect(bulk.single.anchors[arrangePersonOne]!.xUnits, closeTo(7, 1e-6));
    });
  });

  group('automatic history during manual drags', () {
    test('the first drag saves the positions it replaces', () async {
      final server = LayoutHistoryServer();
      final h = await layoutHistoryHarness(server);
      final before = Map.of(server.anchors);

      _drag(h, 7);
      await _drain();

      expect(server.events, ['save:1:0', 'apply']);
      expect(server.snapshots.single.anchors, before);
      expect(server.anchors[arrangePersonOne]!.xUnits, closeTo(7, 1e-6));
    });

    test(
      'repeated drags within ten minutes share one manual snapshot',
      () async {
        final server = LayoutHistoryServer();
        final h = await layoutHistoryHarness(server);
        final before = Map.of(server.anchors);
        for (var i = 0; i < 5; i++) {
          _drag(h, 3.0 + i);
          await _drain();
          h.clock.advance(const Duration(minutes: 2));
        }

        expect(server.batches, hasLength(5));
        expect(server.snapshots, hasLength(1));
        expect(server.snapshots.single.reason, 0);
        expect(server.snapshots.single.anchors, before);
      },
    );

    test(
      'a drag at ten minutes saves again while a drag just before does not',
      () async {
        final server = LayoutHistoryServer();
        final h = await layoutHistoryHarness(server);
        _drag(h, 3);
        await _drain();
        h.clock.advance(
          const Duration(minutes: 10) - const Duration(milliseconds: 1),
        );
        _drag(h, 4);
        await _drain();
        final beforeBoundary = server.snapshots.length;
        final beforeSecondSnapshot = Map.of(server.anchors);

        h.clock.advance(const Duration(milliseconds: 1));
        _drag(h, 5);
        await _drain();

        expect(beforeBoundary, 1);
        expect(server.snapshots, hasLength(2));
        expect(server.snapshots.map((s) => s.reason), [0, 0]);
        expect(server.snapshots.last.anchors, beforeSecondSnapshot);
        expect(
          server.operationIds.toSet(),
          hasLength(server.operationIds.length),
        );
      },
    );

    test('a burst of drags cannot start duplicate manual snapshots', () async {
      final server = LayoutHistoryServer();
      final h = await layoutHistoryHarness(server);
      final before = Map.of(server.anchors);
      for (var i = 0; i < 5; i++) {
        _drag(h, 3.0 + i);
      }
      await _drain();

      expect(server.snapshots, hasLength(1));
      expect(server.snapshots.single.reason, 0);
      expect(server.snapshots.single.anchors, before);
      expect(server.anchors[arrangePersonOne]!.xUnits, closeTo(7, 1e-6));
    });
  });
}
