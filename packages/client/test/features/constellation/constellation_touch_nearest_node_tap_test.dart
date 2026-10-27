import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/synthetic_field.dart';

// #640: on a phone (touch, devicePixelRatio 2) at the minimum zoom the dots of
// a dense cluster sit a few pixels apart and their round tap targets overlap.
// A touch tap must resolve to the dot whose centre is nearest, the same rule
// the mouse click and the hover ring follow.

const _phone = Size(375, 667);
const _devicePixelRatio = 2.0;

/// A mouse on the same phone-sized map keeps its behaviour at either density.
const _mouseDevicePixelRatios = [1.0, 2.0];

/// Screen pixels per anchor unit on the phone's zoom floor.
const _pxPerUnit = 25.5;

const _cluster = ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'];

/// Gaps between neighbouring dots in the dense clusters QA found failing.
const _gapsPx = [4.0, 5.5, 7.0];

/// Fractions along a segment, off the exact middle where two centres tie.
const _fractions = [0.1, 0.2, 0.35, 0.65, 0.8, 0.9];

ConstellationField _clusterField(double gapPx) {
  final base = syntheticConstellationField(size: _cluster.length);
  final projection = base.anchorProjection!;
  ConstellationAnchor pin(String id, double x, double y) => ConstellationAnchor(
    target: ConstellationAnchorTarget.person(id),
    position: ConstellationAnchorPosition(
      xUnits: x,
      yUnits: y,
      coordinateSpaceVersion: 1,
    ),
    revision: projection.revision,
    placedAt: base.loadedAt,
  );
  final gapUnits = gapPx / _pxPerUnit;
  return base.copyWith(
    requests: const [],
    anchorProjection: ConstellationAnchorProjection(
      revision: projection.revision,
      anchors: [
        for (var i = 0; i < _cluster.length; i++)
          pin(_cluster[i], -2 + i * gapUnits, 2),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

void main() {
  late ConstellationCubit cubit;
  late ConstellationPresentationFrameHolder holder;
  late Offset origin;

  Future<void> mountAtMinimumZoom(
    WidgetTester tester,
    double gapPx, {
    double devicePixelRatio = _devicePixelRatio,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetDevicePixelRatio);
    cubit = await loadReferenceCubit(field: _clusterField(gapPx));
    addTearDown(cubit.close);
    holder = ConstellationPresentationFrameHolder();
    await pumpConstellationBody(
      tester,
      cubit,
      size: _phone,
      locale: const Locale('en'),
      presentationFrameHolder: holder,
    );
    await tester.pumpAndSettle();
    final controller = cubit.graphController;
    for (var i = 0; i < 80; i++) {
      controller.zoomBy(0.9);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    origin = tester.getTopLeft(find.byType(ConstellationViewportOverlay));

    final frame = holder.frame!;
    expect(frame.detail, ConstellationDetailLevel.overview);
    for (var i = 0; i + 1 < _cluster.length; i++) {
      expect(
        (frame.bodies['fp:${_cluster[i]}']!.center -
                frame.bodies['fp:${_cluster[i + 1]}']!.center)
            .distance,
        closeTo(gapPx, 1.5),
        reason: 'the cluster dots sit about $gapPx px apart',
      );
    }
  }

  /// Settles the map with nothing selected and returns its current frame.
  Future<ConstellationPresentationFrame> freshFrame(WidgetTester tester) async {
    cubit.selectPerson(null);
    await tester.pumpAndSettle();
    return holder.frame!;
  }

  Future<void> press(
    WidgetTester tester,
    PointerDeviceKind kind,
    Offset viewportPoint,
  ) async {
    final gesture = await tester.createGesture(kind: kind);
    if (kind == PointerDeviceKind.mouse) {
      await gesture.addPointer(location: origin + viewportPoint);
    }
    await gesture.down(origin + viewportPoint);
    await gesture.up();
    if (kind == PointerDeviceKind.mouse) {
      await gesture.removePointer();
    }
    await tester.pumpAndSettle();
  }

  // A finger that lands right after the camera moved (a pinch ending on the
  // zoom floor) is a frame ahead of the presentation frame the map last
  // painted: the tap must still go to the dot whose centre is nearest on the
  // map the finger sees now, i.e. what `resolveConstellationTap` answers for a
  // frame laid out at the camera as it stands.
  for (final gapPx in _gapsPx) {
    group('a dense cluster of dots $gapPx px apart on a phone, '
        'right after the camera moved', () {
      /// The last painted frame re-laid at the camera as it stands now, with
      /// every body and tap target on its current centre (dot sizes are fixed
      /// screen pixels at the zoom floor), so the resolver can be asked what
      /// the map the finger sees would answer.
      ConstellationPresentationFrame currentFrame() {
        final controller = cubit.graphController;
        final stale = holder.frame!;
        Rect moved(Rect rect, String id) => rect.shift(
          controller.sceneToViewportLocal(
                controller.getPositionOrNullForId(id)!,
              ) -
              stale.bodies[id]!.center,
        );
        return ConstellationPresentationFrame(
          snapshot: stale.snapshot,
          cameraRevision: controller.cameraRevision.value,
          detail: stale.detail,
          paintOrder: stale.paintOrder,
          bodies: {
            for (final e in stale.bodies.entries) e.key: moved(e.value, e.key),
          },
          labels: const {},
          tapTargets: {
            for (final e in stale.tapTargets.entries)
              e.key: moved(e.value, e.key),
          },
          chips: const {},
          forcedLabels: const {},
        );
      }

      /// Moves the camera a notch, then taps [pointAt] (viewport px, read on
      /// the moved camera) before the next frame is painted. Returns what the
      /// resolver answers for that point and the dot that got selected.
      Future<(String?, String?)> tapAfterCameraMoved(
        WidgetTester tester,
        Offset Function(Offset Function(String id) centreOf) pointAt,
      ) async {
        final controller = cubit.graphController;
        Offset centreOf(String id) => controller.sceneToViewportLocal(
          controller.getPositionOrNullForId('fp:$id')!,
        );
        cubit.selectPerson(null);
        await tester.pumpAndSettle();
        controller.zoomBy(1.03);
        final point = pointAt(centreOf);
        final expected = resolveConstellationTap(currentFrame(), point);

        final gesture = await tester.createGesture();
        await gesture.down(origin + point);
        await gesture.up();
        await tester.pumpAndSettle();
        return (expected, cubit.state.selectedPersonId);
      }

      testWidgets('a touch tap on the exact centre of each dot selects that '
          'dot, before the next frame is painted', (tester) async {
        await mountAtMinimumZoom(tester, gapPx);
        for (final id in _cluster) {
          final (expected, selected) = await tapAfterCameraMoved(
            tester,
            (centreOf) => centreOf(id),
          );

          expect(expected, 'fp:$id', reason: 'the resolver picks $id');
          expect(selected, id, reason: 'tap on $id');
        }
      });

      testWidgets('a touch tap between two dots follows the nearest-centre '
          'rule, before the next frame is painted', (tester) async {
        await mountAtMinimumZoom(tester, gapPx);
        for (var i = 0; i + 1 < _cluster.length; i++) {
          for (final t in _fractions) {
            final (expected, selected) = await tapAfterCameraMoved(tester, (
              centreOf,
            ) {
              final a = centreOf(_cluster[i]);
              final b = centreOf(_cluster[i + 1]);
              return a + (b - a) * t;
            });

            expect(
              expected,
              'fp:${t < 0.5 ? _cluster[i] : _cluster[i + 1]}',
              reason: 'the resolver picks the nearer dot at t=$t',
            );
            expect(
              'fp:$selected',
              expected,
              reason: 'tap at t=$t from ${_cluster[i]} to ${_cluster[i + 1]}',
            );
          }
        }
      });
    });
  }

  for (final gapPx in _gapsPx) {
    group('a dense cluster of dots $gapPx px apart, mouse unchanged', () {
      for (final dpr in _mouseDevicePixelRatios) {
        testWidgets('a mouse click on the exact centre of each dot selects '
            'that dot at devicePixelRatio $dpr', (tester) async {
          await mountAtMinimumZoom(tester, gapPx, devicePixelRatio: dpr);
          for (final id in _cluster) {
            final frame = await freshFrame(tester);
            await press(
              tester,
              PointerDeviceKind.mouse,
              frame.bodies['fp:$id']!.center,
            );

            expect(cubit.state.selectedPersonId, id, reason: 'click on $id');
          }
        });

        testWidgets('a mouse click between two dots selects the dot whose '
            'centre is nearer at devicePixelRatio $dpr', (tester) async {
          await mountAtMinimumZoom(tester, gapPx, devicePixelRatio: dpr);
          for (var i = 0; i + 1 < _cluster.length; i++) {
            for (final t in _fractions) {
              final frame = await freshFrame(tester);
              final a = frame.bodies['fp:${_cluster[i]}']!.center;
              final b = frame.bodies['fp:${_cluster[i + 1]}']!.center;
              await press(tester, PointerDeviceKind.mouse, a + (b - a) * t);

              expect(
                cubit.state.selectedPersonId,
                t < 0.5 ? _cluster[i] : _cluster[i + 1],
                reason:
                    'click at t=$t from ${_cluster[i]} to ${_cluster[i + 1]}',
              );
            }
          }
        });
      }
    });
  }

  for (final gapPx in _gapsPx) {
    group('a dense cluster of dots $gapPx px apart on a phone', () {
      for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
        testWidgets('a ${kind.name} tap on the exact centre of each dot '
            'selects that dot', (tester) async {
          await mountAtMinimumZoom(tester, gapPx);
          for (final id in _cluster) {
            final frame = await freshFrame(tester);
            await press(tester, kind, frame.bodies['fp:$id']!.center);

            expect(cubit.state.selectedPersonId, id, reason: 'tap on $id');
          }
        });

        testWidgets('a ${kind.name} tap between two dots selects the dot '
            'whose centre is nearer', (tester) async {
          await mountAtMinimumZoom(tester, gapPx);
          for (var i = 0; i + 1 < _cluster.length; i++) {
            for (final t in _fractions) {
              final frame = await freshFrame(tester);
              final a = frame.bodies['fp:${_cluster[i]}']!.center;
              final b = frame.bodies['fp:${_cluster[i + 1]}']!.center;
              final p = a + (b - a) * t;
              final expected = resolveConstellationTap(frame, p);
              await press(tester, kind, p);

              expect(
                expected,
                'fp:${t < 0.5 ? _cluster[i] : _cluster[i + 1]}',
                reason: 'the resolver picks the nearer dot at t=$t',
              );
              expect(
                'fp:${cubit.state.selectedPersonId}',
                expected,
                reason: 'tap at t=$t from ${_cluster[i]} to ${_cluster[i + 1]}',
              );
            }
          }
        });
      }
    });
  }
}
