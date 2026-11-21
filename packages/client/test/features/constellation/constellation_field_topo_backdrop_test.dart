// The Field's topographic backdrop (#1022): a static, world-anchored tile of
// contour lines painted under the tag hulls. It repaints only when the LOD
// band or the theme changes, never while the camera is idle or moves within
// a band.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/util/field_topo_contours.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_topo_backdrop.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_hull_layer.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

class _Camera extends ChangeNotifier {
  double scale = 1;

  void zoomTo(double value) {
    scale = value;
    notifyListeners();
  }
}

Finder get _backdrop => find.byKey(ConstellationFieldTopoBackdrop.backdropKey);

FieldTopoBackdropPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_backdrop).painter! as FieldTopoBackdropPainter;

ConstellationFieldTopoBackdropState _state(WidgetTester tester) =>
    tester.state<ConstellationFieldTopoBackdropState>(
      find.byType(ConstellationFieldTopoBackdrop),
    );

/// Lets the sliced generation and the async tile bake finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 400; i++) {
    if (_state(tester).debugIsSettled) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_state(tester).debugIsSettled, isTrue, reason: 'backdrop settled');
  await tester.pump();
}

Widget _host(_Camera camera, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 600,
      child: ConstellationFieldTopoBackdrop(
        camera: camera,
        cameraScale: () => camera.scale,
      ),
    ),
  ),
);

void main() {
  // Read before any setUp runs: the value flutter_test_config.dart left.
  final enabledByDefault = ConstellationFieldTopoBackdrop.enabled;

  setUp(() {
    ConstellationFieldTopoBackdrop.enabled = true;
  });

  tearDown(() {
    ConstellationFieldTopoBackdrop.enabled = false;
  });

  test('is disabled by default under the test binding', () {
    expect(enabledByDefault, isFalse);
  });

  testWidgets('a disabled backdrop leaves the Field as it was', (
    tester,
  ) async {
    ConstellationFieldTopoBackdrop.enabled = false;
    await mountTagLensBody(tester);
    await settleTagLensBody(tester);
    expect(find.byType(ConstellationFieldTopoBackdrop), findsNothing);
  });

  group('standalone backdrop', () {
    testWidgets('shows the plain surface until the tile is ready', (
      tester,
    ) async {
      final camera = _Camera();
      await tester.pumpWidget(_host(camera, TenturaTheme.light()));
      expect(_painter(tester).shader, isNull, reason: 'nothing drawn yet');

      await _settle(tester);
      final painter = _painter(tester);
      expect(painter.shader, isNotNull);
      expect(painter.band, FieldTopoBand.close);
      expect(
        painter.color,
        TenturaTheme.light().extension<TenturaFieldBackdropColors>()!.line,
      );
      expect(
        tester.renderObject(_backdrop),
        paints..rect(rect: Offset.zero & const Size(800, 600)),
      );
    });

    testWidgets('no repaint while the camera is idle or within a band', (
      tester,
    ) async {
      final camera = _Camera();
      await tester.pumpWidget(_host(camera, TenturaTheme.light()));
      await _settle(tester);
      final bakes = ConstellationFieldTopoBackdrop.debugBakeCount;
      final paints = ConstellationFieldTopoBackdrop.debugPaintCount;

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ConstellationFieldTopoBackdrop.debugPaintCount, paints);

      // Zooming inside the close band changes nothing for the backdrop.
      camera.zoomTo(1.2);
      await tester.pump();
      camera.zoomTo(1.5);
      await tester.pump();
      expect(ConstellationFieldTopoBackdrop.debugPaintCount, paints);
      expect(ConstellationFieldTopoBackdrop.debugBakeCount, bakes);
      expect(_painter(tester).band, FieldTopoBand.close);
      final painter = _painter(tester);
      expect(painter.shouldRepaint(painter), isFalse);
    });

    testWidgets('a band change swaps the tile once, without a blank frame', (
      tester,
    ) async {
      final camera = _Camera();
      await tester.pumpWidget(_host(camera, TenturaTheme.light()));
      await _settle(tester);
      final closeShader = _painter(tester).shader;

      camera.zoomTo(0.6);
      await tester.pump();
      // Until the district tile is baked the close one stays up.
      expect(_painter(tester).shader, isNotNull);

      await _settle(tester);
      expect(_painter(tester).band, FieldTopoBand.district);
      expect(_painter(tester).shader, isNot(same(closeShader)));

      final paints = ConstellationFieldTopoBackdrop.debugPaintCount;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ConstellationFieldTopoBackdrop.debugPaintCount, paints);
    });

    testWidgets('fades out at far overview zoom', (tester) async {
      final camera = _Camera()..scale = 0.15;
      await tester.pumpWidget(_host(camera, TenturaTheme.light()));
      await _settle(tester);
      expect(_painter(tester).band, FieldTopoBand.hidden);
      expect(_painter(tester).shader, isNull);

      camera.zoomTo(0.3);
      await _settle(tester);
      expect(_painter(tester).band, FieldTopoBand.overview);
      expect(_painter(tester).shader, isNotNull);
    });

    testWidgets('a theme switch recolours at once without a rebake', (
      tester,
    ) async {
      final camera = _Camera();
      await tester.pumpWidget(_host(camera, TenturaTheme.light()));
      await _settle(tester);
      final bakes = ConstellationFieldTopoBackdrop.debugBakeCount;
      final paints = ConstellationFieldTopoBackdrop.debugPaintCount;
      final shader = _painter(tester).shader;

      await tester.pumpWidget(_host(camera, TenturaTheme.dark()));
      await tester.pumpAndSettle();

      final dark = TenturaTheme.dark().extension<TenturaFieldBackdropColors>()!;
      expect(_painter(tester).color, dark.line);
      expect(_painter(tester).shader, same(shader));
      expect(ConstellationFieldTopoBackdrop.debugBakeCount, bakes);
      expect(
        ConstellationFieldTopoBackdrop.debugPaintCount,
        greaterThan(paints),
      );
    });
  });

  group('on the Field', () {
    testWidgets('sits in the scene below the tag hull layer', (tester) async {
      final m = await mountTagLensBody(tester);
      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);
      await _settle(tester);

      expect(_backdrop, findsOneWidget);
      // Inside the graph scene: it moves and scales with the camera.
      expect(
        find.ancestor(
          of: _backdrop,
          matching: find.byWidgetPredicate((w) => w is GraphView),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: _backdrop,
          matching: find.byWidgetPredicate((w) => w is InteractiveViewer),
        ),
        findsOneWidget,
        reason: 'inside the transformed scene, not a screen-fixed layer',
      );

      final order = <RenderObject, int>{};
      void visit(RenderObject object) {
        order[object] = order.length;
        object.visitChildren(visit);
      }

      visit(tester.binding.renderViews.single);
      final backdropAt = order[tester.renderObject(_backdrop)]!;
      final hullAt =
          order[tester.renderObject(
            find.byKey(ConstellationTagHullLayer.hullKey(tagLensGarden.id)),
          )]!;
      expect(backdropAt, lessThan(hullAt), reason: 'painted under the hulls');
    });

    testWidgets('follows the camera band of the Field controller', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);
      await settleTagLensBody(tester);
      await _settle(tester);
      final controller = m.field.graphController;
      expect(
        _painter(tester).band,
        fieldTopoBandForZoom(controller.cameraScale),
      );
      controller.zoomBy(0.3 / controller.cameraScale);
      await tester.pump();
      await _settle(tester);
      expect(
        _painter(tester).band,
        fieldTopoBandForZoom(controller.cameraScale),
      );
    });
  });
}
