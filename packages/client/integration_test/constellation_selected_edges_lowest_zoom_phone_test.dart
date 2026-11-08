// Real browser, real stack, 375x667 phone in Russian: a viewer in a chain of
// explicit mutual trust (viewer ⇄ middle ⇄ far) opens the Field and selects
// the middle person. The edges the selection draws at the default zoom stay
// painted when the map is zoomed out to the lowest scale it allows (people
// drawn as overview dots), and every one of them is at least one device pixel
// thick at the default, an intermediate and the lowest zoom. With nothing
// selected, zooming out paints the same edges as the default zoom, and
// clearing the selection and zooming back paints what the default zoom
// painted before anything was selected.
//
// The phone this smoke targets is a 375x667 viewport. BROWSER_DIMENSION sets
// the whole headless Chrome window, whose own toolbar takes 139 px, so the
// run uses a 375x806 window to give the app a 375x667 viewport:
//   BROWSER_DIMENSION=375x806 ./scripts/run_client_integration_web_local.sh \
//     integration_test/constellation_selected_edges_lowest_zoom_phone_test.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// The app's viewport on the target phone (not the browser window size).
const _phoneViewport = Size(375, 667);

String _pair(String x, String y) => x.compareTo(y) <= 0 ? '$x–$y' : '$y–$x';

/// Canvas that keeps the scene thickness of every visible (alpha > 0) mark an
/// edge can be drawn with: stroked or filled lines, paths, rects and rounded
/// rects. Circles and ovals (end dots) are decorations and left out.
final class _MarkRecordingCanvas implements Canvas {
  final thicknesses = <double>[];

  void _add(double thickness, Paint paint) {
    if (paint.color.a == 0 || thickness <= 0) return;
    thicknesses.add(thickness);
  }

  /// A long thin filled quad of length L and thickness t has a perimeter of
  /// about 2L + 2t and a bounds diagonal of about L.
  static double _shapeThickness(double perimeter, Rect bounds) =>
      perimeter / 2 -
      math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if ((p2 - p1).distance == 0) return;
    _add(paint.strokeWidth, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    final length = path.computeMetrics().fold<double>(
      0,
      (sum, m) => sum + m.length,
    );
    if (length == 0) return;
    _add(
      paint.style == PaintingStyle.stroke
          ? paint.strokeWidth
          : _shapeThickness(length, path.getBounds()),
      paint,
    );
  }

  @override
  void drawRect(Rect rect, Paint paint) => _add(
    paint.style == PaintingStyle.stroke
        ? paint.strokeWidth
        : math.min(rect.width, rect.height),
    paint,
  );

  @override
  void drawRRect(RRect rrect, Paint paint) => drawRect(rrect.outerRect, paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

GraphView<dynamic, dynamic> _graphView(WidgetTester tester) =>
    tester.widget<GraphView<dynamic, dynamic>>(
      find.byWidgetPredicate((w) => w is GraphView),
    );

/// Every edge of the Field's scene handed to the mounted Field edge painter
/// (as the graph view's edge layer does): pair of domain ids → scene
/// thickness of its thickest visible mark. Edges with no visible mark are
/// left out.
Map<String, double> _paintedEdges(WidgetTester tester) {
  final painter = _graphView(tester).edgePainter;
  expect(painter, isA<ConstellationEdgePainter>());
  final snapshot = readConstellationCubit(
    tester,
  ).graphController.renderSnapshot;
  final result = <String, double>{};
  for (final edge in snapshot.topology.edgesById.values) {
    final payload = edge.payload;
    if (payload.source.id == payload.destination.id) continue;
    final src = snapshot.resolvePosition(edge.sourceId);
    final dst = snapshot.resolvePosition(edge.destinationId);
    if (src == null || dst == null) continue;
    final canvas = _MarkRecordingCanvas();
    (painter as ConstellationEdgePainter).paint(
      canvas,
      payload,
      Offset(src.x, src.y),
      Offset(dst.x, dst.y),
    );
    if (canvas.thicknesses.isEmpty) continue;
    final pair = _pair(payload.source.id, payload.destination.id);
    result[pair] = math.max(
      result[pair] ?? 0,
      canvas.thicknesses.reduce(math.max),
    );
  }
  return result;
}

double _cameraScale(WidgetTester tester) =>
    readConstellationCubit(tester).graphController.cameraScale;

Future<void> _zoomTo(WidgetTester tester, double scale) async {
  final controller = readConstellationCubit(tester).graphController;
  controller.zoomBy(scale / controller.cameraScale);
  await pumpBounded(tester, frames: 24);
  expect(tester.takeException(), isNull);
}

ConstellationDetailLevel _detail(WidgetTester tester) =>
    RepositoryProvider.of<ConstellationZoomLevelController>(
      tester.element(find.byType(ConstellationBody)),
    ).value;

/// Every edge in [pairs] is painted, each at least one device pixel thick at
/// devicePixelRatio 1 and 2 (and at the browser's own ratio).
void _expectPaintedAtLeastOnePixel(
  WidgetTester tester,
  Set<String> pairs,
  String label,
) {
  final scale = _cameraScale(tester);
  final painted = _paintedEdges(tester);
  for (final pair in pairs.toList()..sort()) {
    final thickness = painted[pair];
    expect(
      thickness,
      isNotNull,
      reason:
          '$label (scale $scale): $pair must be painted, painted: '
          '${painted.keys.toList()..sort()}',
    );
    for (final devicePixelRatio in {1.0, 2.0, tester.view.devicePixelRatio}) {
      expect(
        thickness! * scale * devicePixelRatio,
        greaterThanOrEqualTo(1),
        reason:
            '$label (scale $scale, devicePixelRatio $devicePixelRatio): '
            '$pair is $thickness scene px thick',
      );
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on a 375x667 phone in Russian, a selected person keeps their '
      'edges painted at the lowest zoom', (tester) async {
    e2eDrainExceptions = false;
    await launchApp(app.main);
    await pumpBounded(tester);

    // Eve ⇄ Carol and Carol ⇄ Bob trust each other explicitly. Eve is the
    // viewer; Carol is selected.
    final fixture = await bootstrapWitnessFixture(
      runId: uniqueRunId('selected-edges-lowest-zoom'),
    );
    final viewer = fixture.eveUserId;
    final middle = fixture.carolUserId;
    final far = fixture.bobUserId;
    await loginAs(tester, fixture.eveEmail);
    await pumpBounded(tester, frames: 12);

    final settings = GetIt.I<SettingsCubit>();
    final localeBefore = settings.state.localePreference;
    await settings.setLocalePreference(kLocalePreferenceRu);
    addTearDown(() => settings.setLocalePreference(localeBefore));
    await pumpBounded(tester, frames: 12);

    await openConstellation(tester);
    await setConstellationViewMode(tester, ConstellationViewMode.map);
    bool chainOnField() {
      final ids = {
        for (final node in readConstellationCubit(
          tester,
        ).graphController.renderSnapshot.topology.nodesById.values)
          node.payload.id,
      };
      return ids.contains(middle) && ids.contains(far);
    }

    var reloads = 0;
    await pumpUntilAsync(
      tester,
      () async {
        if (chainOnField()) {
          return true;
        }
        if (++reloads % 15 == 0) {
          await reloadConstellation(tester);
        }
        return chainOnField();
      },
      label: 'both people of the chain on the Field',
      timeout: const Duration(seconds: 90),
    );

    final context = tester.element(find.byType(ConstellationBody));
    expect(
      tester.view.physicalSize / tester.view.devicePixelRatio,
      _phoneViewport,
      reason: 'the app viewport must be 375x667 (a 375x806 window)',
    );
    expect(Localizations.localeOf(context).languageCode, 'ru');

    // Nothing selected: what the default zoom paints, and the lowest zoom
    // adds nothing to it.
    final cubit = readConstellationCubit(tester);
    expect(cubit.state.selectedPersonId, isNull);
    expect(cubit.state.selectedRequestId, isNull);
    final defaultScale = _cameraScale(tester);
    final lowestScale = _graphView(tester).minScale;
    expect(lowestScale, lessThan(defaultScale));
    final ambient = _paintedEdges(tester).keys.toSet();

    await _zoomTo(tester, lowestScale);
    expect(_detail(tester), ConstellationDetailLevel.overview);
    final ambientLowest = _paintedEdges(tester).keys.toSet();
    expect(
      ambientLowest,
      ambient,
      reason:
          'nothing selected: the lowest zoom paints the edges the default '
          'zoom paints, painted: ${ambientLowest.toList()..sort()}',
    );
    _expectPaintedAtLeastOnePixel(
      tester,
      ambientLowest,
      'nothing selected, lowest zoom',
    );
    await _zoomTo(tester, defaultScale);

    // The middle person selected at the default zoom: the edges the
    // selection adds, plus any already drawn that end at them.
    await selectConstellationPersonNode(tester, middle);
    await pumpBounded(tester, frames: 24);
    expect(tester.takeException(), isNull);
    final withSelection = _paintedEdges(tester).keys.toSet();
    final selectionEdges = {
      for (final pair in withSelection)
        if (!ambient.contains(pair) || pair.split('–').contains(middle)) pair,
    };
    expect(
      selectionEdges,
      containsAll([_pair(viewer, middle), _pair(middle, far)]),
      reason: 'selecting the middle person draws both trust hops',
    );

    for (final (scale, zoom) in [
      (defaultScale, 'default zoom'),
      ((defaultScale + lowestScale) / 2, 'intermediate zoom'),
      (lowestScale, 'lowest zoom'),
    ]) {
      await _zoomTo(tester, scale);
      expect(
        readConstellationCubit(tester).state.selectedPersonId,
        middle,
        reason: 'zooming keeps the selection',
      );
      _expectPaintedAtLeastOnePixel(tester, selectionEdges, zoom);
    }
    expect(_detail(tester), ConstellationDetailLevel.overview);
    final lowest = _paintedEdges(tester).keys.toSet();
    expect(
      withSelection.containsAll(lowest),
      isTrue,
      reason:
          'the lowest zoom paints no edge the default zoom does not, '
          'painted: ${lowest.toList()..sort()}',
    );

    // Clearing the selection at the lowest zoom, then zooming back: what the
    // default zoom painted before anything was selected.
    readConstellationCubit(tester).selectPerson(null);
    await pumpBounded(tester, frames: 24);
    final clearedLowest = _paintedEdges(tester).keys.toSet();
    expect(
      ambient.containsAll(clearedLowest),
      isTrue,
      reason:
          'selection cleared: the lowest zoom paints no edge the default '
          'zoom paints with nothing selected, painted: '
          '${clearedLowest.toList()..sort()}',
    );
    await _zoomTo(tester, defaultScale);
    expect(_detail(tester), isNot(ConstellationDetailLevel.overview));
    expect(
      _paintedEdges(tester).keys.toSet(),
      ambient,
      reason: 'back at the default zoom with nothing selected',
    );

    await selectConstellationPersonNode(tester, middle);
    await pumpBounded(tester, frames: 24);
    _expectPaintedAtLeastOnePixel(
      tester,
      selectionEdges,
      'reselected at the default zoom',
    );
  });
}
