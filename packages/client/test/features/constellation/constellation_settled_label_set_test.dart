import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';

import 'fixtures/constellation_reference_fixture.dart';

typedef _Settled = ({
  double scale,
  ConstellationDetailLevel detail,
  Map<GraphNodeId, Offset> centres,
  Set<GraphNodeId> labels,
  Set<String> chips,
});

void main() {
  group('label set at a settled scale', () {
    late ConstellationCubit cubit;
    late ConstellationPresentationFrameHolder holder;

    Future<void> pump(WidgetTester tester, Size size) async {
      cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: size,
        locale: const Locale('en'),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();
    }

    double scaleNow() => cubit.graphController.cameraScale;

    Future<void> zoomToScale(WidgetTester tester, double target) async {
      for (var i = 0; i < 80 && (scaleNow() - target).abs() > 1e-9; i++) {
        final step = (target / scaleNow()).clamp(0.9, 1.1);
        cubit.graphController.zoomBy(step);
        await tester.pump();
      }
    }

    // Mouse-wheel zoom about the viewport centre, as a desktop user zooms:
    // Flutter turns a scroll of `dy` into a scale factor of exp(-dy / 200).
    Future<void> wheelToScale(
      WidgetTester tester,
      Size size,
      double target,
    ) async {
      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        wheel.hover(Offset(size.width / 2, size.height / 2)),
      );
      for (var i = 0; i < 80 && (scaleNow() - target).abs() > 1e-6; i++) {
        final factor = (target / scaleNow()).clamp(0.8, 1.25);
        await tester.sendEventToBinding(
          wheel.scroll(Offset(0, -200 * math.log(factor))),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<_Settled> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      final frame = holder.frame!;
      return (
        scale: scaleNow(),
        detail: frame.detail,
        centres: {
          for (final e in frame.bodies.entries) e.key: e.value.center,
        },
        labels: frame.labels.keys.toSet(),
        chips: frame.chips.keys.toSet(),
      );
    }

    void expectSameSettledScene(_Settled fromFar, _Settled fromNear) {
      expect(fromFar.scale, closeTo(fromNear.scale, 1e-6));
      expect(fromFar.detail, fromNear.detail);
      expect(fromFar.labels, fromNear.labels);
      expect(fromFar.chips, fromNear.chips);
      // Same scale, same node positions: the label set is the only variable.
      expect(fromFar.centres.keys.toSet(), fromNear.centres.keys.toSet());
      for (final entry in fromFar.centres.entries) {
        final other = fromNear.centres[entry.key]!;
        expect(entry.value.dx, closeTo(other.dx, 0.5), reason: '${entry.key}');
        expect(entry.value.dy, closeTo(other.dy, 0.5), reason: '${entry.key}');
      }
    }

    for (final size in [const Size(1200, 900), const Size(375, 547)]) {
      for (final target in [0.4, 0.45, 0.46, 0.5, 0.6, 0.86]) {
        testWidgets(
          'scale $target on ${size.width.toInt()}px shows the same labels '
          'whether the wheel reached it from the minimum zoom or from a '
          'closer zoom',
          (tester) async {
            await pump(tester, size);

            // Far below the floor: the wheel stops at the minimum zoom.
            await wheelToScale(tester, size, 0.01);
            await wheelToScale(tester, size, target);
            final fromFar = await settle(tester);

            await wheelToScale(tester, size, 3);
            await wheelToScale(tester, size, target);
            final fromNear = await settle(tester);

            expectSameSettledScene(fromFar, fromNear);
          },
        );
      }
    }

    // While a pointer is down the level holds back near a threshold, so a
    // pinch jittering on the edge does not flicker; once the pointer is
    // released the level must follow the scale again, with no further camera
    // movement to prompt it.
    for (final size in [const Size(1200, 900), const Size(375, 547)]) {
      for (final (:from, :target) in [
        (from: 0.1, target: 0.46),
        (from: 1.5, target: 0.44),
      ]) {
        testWidgets(
          'scale $target zoomed from $from while a pointer is down on '
          '${size.width.toInt()}px shows the same labels once released as '
          'with no pointer down',
          (tester) async {
            await pump(tester, size);

            await zoomToScale(tester, from);
            await zoomToScale(tester, target);
            final reference = await settle(tester);

            await zoomToScale(tester, from);
            await tester.pumpAndSettle();
            final gesture = await tester.startGesture(
              Offset(size.width / 2, size.height / 2),
              kind: PointerDeviceKind.mouse,
            );
            await zoomToScale(tester, target);
            await gesture.up();
            final afterRelease = await settle(tester);

            expectSameSettledScene(afterRelease, reference);
          },
        );
      }
    }
  });
}
