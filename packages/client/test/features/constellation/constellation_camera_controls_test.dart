import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/test_ids.dart';
import 'fixtures/constellation_reference_fixture.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'dart:math' as math;

Matrix4 _cameraMatrix(WidgetTester tester) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  return viewer.transformationController!.value.clone();
}

Rect _usableViewport(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool contextPanelVisible,
}) {
  final context = tester.element(find.byType(ConstellationBody));
  final insets = ConstellationCameraControls.cameraViewportInsets(
    context,
    contextPanelVisible: contextPanelVisible,
  );
  final pixel = cubit.graphController.viewportSize!;
  return Rect.fromLTRB(
    insets.left,
    insets.top,
    pixel.width - insets.right,
    pixel.height - insets.bottom,
  );
}

Rect _sceneNodeRect(ConstellationCubit cubit, String graphId) {
  final snapshot = cubit.graphController.renderSnapshot;
  final point = snapshot.resolvePosition(graphId);
  final sceneNode = snapshot.topology.nodesById[graphId];
  if (point == null || sceneNode == null) {
    return Rect.zero;
  }
  final bounds = constellationPlacedNodeBounds(
    centre: (x: point.x, y: point.y),
    footprint: cubit.layoutFootprints[graphId],
    size: (
      width: sceneNode.size.width,
      height: sceneNode.size.height,
    ),
  );
  return Rect.fromLTRB(
    bounds.left,
    bounds.top,
    bounds.right,
    bounds.bottom,
  );
}

void _expectFootprintsInsideUsable(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required bool contextPanelVisible,
}) {
  final controller = cubit.graphController;
  final usable = _usableViewport(
    tester,
    cubit,
    contextPanelVisible: contextPanelVisible,
  );
  for (final graphId in controller.renderSnapshot.topology.nodesById.keys) {
    if (controller.renderSnapshot.resolvePosition(graphId) == null) {
      continue;
    }
    final sceneRect = _sceneNodeRect(cubit, graphId);
    final topLeft = controller.sceneToViewportLocal(sceneRect.topLeft);
    final bottomRight = controller.sceneToViewportLocal(sceneRect.bottomRight);
    final viewportRect = Rect.fromPoints(topLeft, bottomRight);
    expect(
      usable.left - 1,
      lessThanOrEqualTo(viewportRect.left),
      reason: '$graphId left outside usable',
    );
    expect(
      usable.top - 1,
      lessThanOrEqualTo(viewportRect.top),
      reason: '$graphId top outside usable',
    );
    expect(
      viewportRect.right,
      lessThanOrEqualTo(usable.right + 1),
      reason: '$graphId right outside usable',
    );
    expect(
      viewportRect.bottom,
      lessThanOrEqualTo(usable.bottom + 1),
      reason: '$graphId bottom outside usable',
    );
  }
}

Future<void> _disorientCamera(ConstellationCubit cubit) async {
  final controller = cubit.graphController;
  controller.zoomBy(0.3);
  const egoGraphId = '${TenturaGraphNodeKind.fieldPerson}:ego';
  final egoPoint = controller.renderSnapshot.resolvePosition(egoGraphId);
  if (egoPoint != null) {
    controller.jumpToPosition(
      Offset(egoPoint.x + 280, egoPoint.y + 220),
    );
  }
}

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

final class _NonLinearTextScaler extends TextScaler {
  @override
  double get textScaleFactor => 1.0;

  @override
  double scale(double fontSize) => math.min(fontSize * 2, fontSize + 6);

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = 4}) =>
      this;
}

void main() {
  group('ConstellationCameraControls', () {
    testWidgets('fit whole field after zoom and pan', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pump();

      _expectFootprintsInsideUsable(tester, cubit, contextPanelVisible: false);
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(1.0));
    });

    testWidgets('center on ego restores scale and centres in usable region', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();

      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      await tester.pump();

      expect(cubit.graphController.cameraScale, closeTo(1.0, 0.001));
      final usable = _usableViewport(tester, cubit, contextPanelVisible: false);
      const egoGraphId = '${TenturaGraphNodeKind.fieldPerson}:ego';
      final egoScene = cubit.graphController.renderSnapshot.resolvePosition(
        egoGraphId,
      )!;
      final egoViewport = cubit.graphController.sceneToViewportLocal(
        Offset(egoScene.x, egoScene.y),
      );
      expect(egoViewport.dx, closeTo(usable.center.dx, 0.5));
      expect(egoViewport.dy, closeTo(usable.center.dy, 0.5));
    });

    testWidgets('controls disabled during draggingExisting', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await _disorientCamera(cubit);
      await tester.pump();
      final matrixBefore = _cameraMatrix(tester);

      cubit.beginDragExisting(
        target: ConstellationAnchorTarget.person('am'),
      );
      await tester.pump();

      final fitButton = tester.widget<IconButton>(
        find.byKey(TestIds.key(TestIds.constellationFitAll)),
      );
      final centerButton = tester.widget<IconButton>(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      expect(fitButton.onPressed, isNull);
      expect(centerButton.onPressed, isNull);

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
      );
      await tester.pump();

      expect(
        _cameraMatrix(tester).storage,
        matrixBefore.storage,
      );
    });

    testWidgets('single-node ego-only field fits without degenerate crash', (
      tester,
    ) async {
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 9),
        context: '',
        peers: const [],
        edges: const [],
        requests: const [],
      );
      final cubit = await loadReferenceCubit(field: field);
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pump();

      expect(cubit.graphController.cameraScale, closeTo(1.0, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('camera transform stable across field mutations', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      final baseline = _cameraMatrix(tester);

      void expectUnchanged() {
        expect(
          _cameraMatrix(tester).storage,
          baseline.storage,
          reason: 'camera moved unexpectedly',
        );
      }

      cubit.toggleSatelliteOverflow('ego');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();

      cubit.setFilterCapabilitySlugs({'tools'});
      await tester.pumpAndSettle();
      expectUnchanged();

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      cubit.setViewMode(ConstellationViewMode.map);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();

      await cubit.load();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expectUnchanged();
    });
  });

  // --- merged from constellation_viewport_overlay_test.dart ---

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
    testWidgets('pinned nodes and requests respect corner placement', (
      tester,
    ) async {
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

  // --- merged from constellation_label_budget_widget_test.dart ---

  testWidgets('body syncs dimensionless text scale ratio from TextScaler', (
    tester,
  ) async {
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: TextScaler.linear(1.0),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, 1.0);

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: TextScaler.linear(1.3),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, closeTo(1.3, 1e-9));

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: _NonLinearTextScaler(),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, closeTo(19 / 13, 1e-9));
  });
}
