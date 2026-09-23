import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/test_ids.dart';

import 'fixtures/constellation_reference_fixture.dart';

List<ConstellationAnchor> _pinnedReferenceAnchors() {
  final loadedAt = DateTime.utc(2026, 9, 9, 12);
  final revision = ConstellationAnchorRevision(BigInt.one);
  return [
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person('am'),
      position: const ConstellationAnchorPosition(
        xUnits: 4,
        yUnits: -2,
        coordinateSpaceVersion: 1,
      ),
      revision: revision,
      placedAt: loadedAt,
    ),
    ConstellationAnchor(
      target: ConstellationAnchorTarget.beacon('req-in-2'),
      position: const ConstellationAnchorPosition(
        xUnits: -3,
        yUnits: 4,
        coordinateSpaceVersion: 1,
      ),
      revision: revision,
      placedAt: loadedAt,
    ),
  ];
}

Rect _globalRect(WidgetTester tester, Finder finder) {
  return tester.getTopLeft(finder) & tester.getSize(finder);
}

Iterable<Rect> _placedLabelRects(WidgetTester tester) sync* {
  for (final id in ['fp:ego', 'fp:am', 'fp:in', 'fp:sm']) {
    final finder = find.byKey(ValueKey('constellation.label.$id'));
    if (finder.evaluate().isEmpty) {
      continue;
    }
    yield _globalRect(tester, finder);
  }
  for (final id in [
    'fr:req-ego-1',
    'fr:req-in-2',
    'fr:req-am-1',
    'fr:req-sm-1',
  ]) {
    final finder = find.byKey(ValueKey('constellation.label.$id'));
    if (finder.evaluate().isEmpty) {
      continue;
    }
    yield _globalRect(tester, finder);
  }
}

void _expectBadgeUpperCorner({
  required Rect badgeRect,
  required Rect bodyRect,
  required bool onEndSide,
}) {
  expect(badgeRect.center.dy, lessThan(bodyRect.center.dy));
  if (onEndSide) {
    expect(badgeRect.center.dx, greaterThan(bodyRect.center.dx));
  } else {
    expect(badgeRect.center.dx, lessThan(bodyRect.center.dx));
  }
  expect(badgeRect.bottom, lessThanOrEqualTo(bodyRect.bottom + 0.5));
}

Finder _nodeStack(Finder bodyFinder) {
  return find.ancestor(
    of: bodyFinder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Stack &&
          widget.clipBehavior == Clip.none &&
          widget.alignment == Alignment.center,
    ),
  );
}

void main() {
  group('ConstellationViewportOverlay integration', () {
    testWidgets('sm label stays readable after zoom (UI-03)', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      cubit.graphController.zoomBy(0.5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final label = find.byKey(const ValueKey('constellation.label.fp:sm'));
      expect(label, findsOneWidget);
      expect(
        tester.getSize(label).height,
        greaterThanOrEqualTo(13 * 1.35 - 0.01),
      );
      final text = tester.widget<Text>(
        find.descendant(of: label, matching: find.byType(Text)),
      );
      expect(text.style?.fontSize, 13);
    });

    testWidgets('ego overflow chip tracks body pan', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      final chip = find.byKey(const Key('constellation.overflow.ego'));
      final egoBody = find.byKey(TestIds.key(TestIds.graphNode('ego')));
      expect(chip, findsOneWidget);
      expect(egoBody, findsOneWidget);

      final controller = cubit.graphController;
      const egoGraphId = '${TenturaGraphNodeKind.fieldPerson}:ego';
      final scenePoint = controller.renderSnapshot.resolvePosition(egoGraphId)!;
      final scene = Offset(scenePoint.x, scenePoint.y);

      final chipRectBefore = _globalRect(tester, chip);
      final bodyRectBefore = _globalRect(tester, egoBody);
      expect(
        (chipRectBefore.center - bodyRectBefore.center).distance,
        lessThan(2 * kMinInteractiveDimension + 80),
      );

      controller.jumpToPosition(scene + const Offset(100, 0));
      await tester.pumpAndSettle();

      final bodyViewport = controller.sceneToViewportLocal(scene);
      final chipCenter = _globalRect(tester, chip).center;
      expect(
        (chipCenter - bodyViewport).distance,
        lessThan(2 * kMinInteractiveDimension + 80),
      );
    });

    testWidgets('chip toggles expand and shows fewer copy', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        locale: const Locale('ru'),
      );
      await tester.pumpAndSettle();

      final chip = find.byKey(const Key('constellation.overflow.ego'));
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(cubit.isSatelliteOverflowExpanded('ego'), isTrue);
      expect(find.text('Свернуть'), findsOneWidget);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(cubit.isSatelliteOverflowExpanded('ego'), isFalse);
    });

    testWidgets('no layout exceptions at text scale 2.0', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        textScale: 2.0,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Constellation pin/status badges (UI-14)', () {
    testWidgets('pinned nodes and requests respect corner placement', (tester) async {
      final field = constellationReferenceField(
        anchors: _pinnedReferenceAnchors(),
      );
      final cubit = await loadReferenceCubit(field: field);
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();

      await pumpConstellationBody(
        tester,
        cubit,
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();

      final labelRects = _placedLabelRects(tester).toList();

      final amBody = find.byKey(TestIds.key(TestIds.graphNode('am')));
      final amStack = _nodeStack(amBody);
      final amPin = find.descendant(
        of: amStack,
        matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
      );
      expect(amPin, findsOneWidget);
      _expectBadgeUpperCorner(
        badgeRect: _globalRect(tester, amPin),
        bodyRect: _globalRect(tester, amBody),
        onEndSide: true,
      );

      final reqBody = find.byKey(TestIds.key(TestIds.graphNode('req-in-2')));
      final reqStack = _nodeStack(reqBody);
      final reqPin = find.descendant(
        of: reqStack,
        matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
      );
      final reqStatus = find.descendant(
        of: reqStack,
        matching: find.byKey(
          TestIds.key(TestIds.constellationRequestStatusMarker),
        ),
      );
      expect(reqPin, findsOneWidget);
      expect(reqStatus, findsOneWidget);
      _expectBadgeUpperCorner(
        badgeRect: _globalRect(tester, reqPin),
        bodyRect: _globalRect(tester, reqBody),
        onEndSide: true,
      );
      _expectBadgeUpperCorner(
        badgeRect: _globalRect(tester, reqStatus),
        bodyRect: _globalRect(tester, reqBody),
        onEndSide: false,
      );

      for (final badgeRect in [
        _globalRect(tester, amPin),
        _globalRect(tester, reqPin),
        _globalRect(tester, reqStatus),
      ]) {
        for (final labelRect in labelRects) {
          expect(badgeRect.overlaps(labelRect), isFalse);
        }
      }

      final smBody = find.byKey(TestIds.key(TestIds.graphNode('sm')));
      final smStack = _nodeStack(smBody);
      expect(
        find.descendant(
          of: smStack,
          matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: smStack,
          matching: find.byKey(
            TestIds.key(TestIds.constellationRequestStatusMarker),
          ),
        ),
        findsNothing,
      );

      expect(holder.frame, isNotNull);
    });

    testWidgets('RTL pin badges sit on visual end side', (tester) async {
      final field = constellationReferenceField(
        anchors: _pinnedReferenceAnchors(),
      );
      final cubit = await loadReferenceCubit(field: field);
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        locale: const Locale('ru'),
        textDirection: TextDirection.rtl,
      );
      await tester.pumpAndSettle();

      final amBody = find.byKey(TestIds.key(TestIds.graphNode('am')));
      final amStack = _nodeStack(amBody);
      final amPin = find.descendant(
        of: amStack,
        matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
      );
      expect(amPin, findsOneWidget);
      _expectBadgeUpperCorner(
        badgeRect: _globalRect(tester, amPin),
        bodyRect: _globalRect(tester, amBody),
        onEndSide: false,
      );
    });
  });
}
