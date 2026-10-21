@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';

bool _isLabel(Widget w, {String? except}) {
  final key = w.key;
  if (key is! ValueKey<String>) return false;
  return key.value.startsWith('constellation.label.') && key.value != except;
}

void main() {
  group('Constellation overlay during a node drag', () {
    testWidgets('does not rebuild the overlay or re-run placement when one '
        'node moves, and the moved node label still follows', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();

      final controller = cubit.graphController;
      cubit.beginDragExisting(target: ConstellationAnchorTarget.person('am'));
      await tester.pumpAndSettle();

      // Count rebuilds of every builder element below the overlay: the
      // overlay's own listenable builder is the one that must stay quiet.
      final overlay = tester.element(find.byType(ConstellationViewportOverlay));
      var overlayBuilderBuilds = 0;
      final previousCallback = debugOnRebuildDirtyWidget;
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousCallback?.call(element, builtOnce);
        if (element.widget is ListenableBuilder) {
          var below = false;
          element.visitAncestorElements((a) {
            if (identical(a, overlay)) below = true;
            return !below;
          });
          if (below) overlayBuilderBuilds++;
        }
      };

      // Positive control: a zoom must still rebuild and re-place the overlay.
      constellationPlacementCount = 0;
      controller.zoomBy(1.25);
      await tester.pumpAndSettle();
      expect(overlayBuilderBuilds, greaterThan(0));
      expect(constellationPlacementCount, greaterThan(0));

      final labelFinder = find.byWidgetPredicate((w) => _isLabel(w));
      final otherLabels = find.byWidgetPredicate(
        (w) => _isLabel(w, except: 'constellation.label.fp:am'),
      );
      final labelKeysBefore = tester
          .widgetList(labelFinder)
          .map((w) => w.key)
          .toSet();
      final otherBefore = {
        for (final w in tester.widgetList(otherLabels)) w.key: w,
      };
      expect(otherBefore, isNotEmpty);
      expect(holder.frame!.labels, contains('fp:am'));
      final chipsBefore = tester
          .widgetList(find.byType(ConstellationOverflowGroup))
          .toList();
      expect(chipsBefore, isNotEmpty, reason: 'fixture must mount chips');
      expect(holder.frame!.chips, isNotEmpty);

      final positionBefore = controller.getPositionForId('fp:am');
      final labelBefore = holder.frame!.labels['fp:am']!;
      final chipRectsBefore = Map<String, Rect>.of(holder.frame!.chips);
      overlayBuilderBuilds = 0;
      constellationPlacementCount = 0;
      for (var i = 1; i <= 3; i++) {
        cubit.updateDragPresentation(
          nodeId: 'am',
          sceneCentre: positionBefore + Offset(10.0 * i, 6.0 * i),
        );
        await tester.pump();
      }
      final moved = controller.getPositionForId('fp:am') - positionBefore;
      expect(moved.dx, greaterThan(0));
      expect(moved.dy, greaterThan(0));

      expect(
        overlayBuilderBuilds,
        0,
        reason: 'A drag move must not rebuild the overlay builder',
      );
      expect(
        constellationPlacementCount,
        0,
        reason: 'A drag move must not re-run label/chip placement',
      );

      // Visible behaviour is unchanged: same labels, other plates reused,
      // and the moved node label follows the node.
      expect(
        tester.widgetList(labelFinder).map((w) => w.key).toSet(),
        labelKeysBefore,
      );
      for (final w in tester.widgetList(otherLabels)) {
        expect(identical(w, otherBefore[w.key]), isTrue, reason: '${w.key}');
      }
      final chipsAfter = tester
          .widgetList(find.byType(ConstellationOverflowGroup))
          .toList();
      expect(chipsAfter.length, chipsBefore.length);
      for (var i = 0; i < chipsBefore.length; i++) {
        expect(identical(chipsAfter[i], chipsBefore[i]), isTrue);
      }
      final labelAfter = holder.frame!.labels['fp:am']!;
      expect(labelAfter.center.dx, greaterThan(labelBefore.center.dx));
      expect(labelAfter.center.dy, greaterThan(labelBefore.center.dy));
      final scale = controller.cameraScale;
      expect(
        (labelAfter.center - labelBefore.center - moved * scale).distance,
        lessThan(1),
        reason: 'The dragged node label must track the node 1:1',
      );
      expect(holder.frame!.chips.keys.toSet(), chipRectsBefore.keys.toSet());
    });

    testWidgets('a camera pan does not rebuild the overlay builder or '
        're-run placement', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();

      final overlay = tester.element(find.byType(ConstellationViewportOverlay));
      var builds = 0;
      final previousCallback = debugOnRebuildDirtyWidget;
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousCallback?.call(element, builtOnce);
        if (element.widget.runtimeType.toString() == 'ListenableBuilder') {
          var below = false;
          element.visitAncestorElements((a) {
            if (identical(a, overlay)) below = true;
            return !below;
          });
          if (below) builds++;
        }
      };
      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      constellationPlacementCount = 0;
      camera.value = camera.value.clone()
        ..setTranslationRaw(
          camera.value.storage[12] + 12,
          camera.value.storage[13] + 8,
          camera.value.storage[14],
        );
      await tester.pump();
      expect(builds, 0);
      expect(constellationPlacementCount, 0);
    });
  });
}
