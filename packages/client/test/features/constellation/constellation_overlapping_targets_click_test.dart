import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/synthetic_field.dart';

// #640: at the overview and district zoom levels the round targets of neighbouring people overlap.
// Whatever reaches a click on the map (the pointer, or a tap action a browser
// or screen reader delivers through the semantics tree) must resolve to the
// node whose centre is nearest, the same node the hover ring is drawn on.

/// A pair about as far apart as a desktop QA pass found it failing.
const _pairGapPx = 24.0;

/// A dense run of dots, as close as on a phone's smallest map.
const _clusterGapPx = 7.0;

const _pair = ['p0', 'p1'];
const _cluster = ['p2', 'p3', 'p4', 'p5', 'p6'];
const _everyone = [..._pair, ..._cluster];

/// A layout is a viewport at a detail level: the camera scale it settles on
/// (null: the zoom floor), how many screen pixels one anchor unit is there,
/// and where in anchor units the pair and the cluster sit.
typedef _Viewport = ({
  String name,
  Size size,
  ConstellationDetailLevel detail,
  double? scale,
  double pxPerUnit,
  double pairX,
  double clusterX,
  double y,
});

/// Screen pixels per anchor unit at camera scale 1.
const _pxPerUnitAtScale1 = 170.0;

const _districtScale = 0.6;

const _viewports = <_Viewport>[
  (
    name: 'desktop overview',
    size: Size(1200, 900),
    detail: ConstellationDetailLevel.overview,
    scale: null,
    pxPerUnit: 49.8,
    pairX: 2,
    clusterX: -2,
    y: 2,
  ),
  (
    name: 'phone overview',
    size: Size(375, 667),
    detail: ConstellationDetailLevel.overview,
    scale: null,
    pxPerUnit: 25.5,
    pairX: 2,
    clusterX: -2,
    y: 2,
  ),
  (
    name: 'desktop district',
    size: Size(1200, 900),
    detail: ConstellationDetailLevel.district,
    scale: _districtScale,
    pxPerUnit: _pxPerUnitAtScale1 * _districtScale,
    pairX: 0.7,
    clusterX: -0.9,
    y: 0.7,
  ),
  (
    name: 'phone district',
    size: Size(375, 667),
    detail: ConstellationDetailLevel.district,
    scale: _districtScale,
    pxPerUnit: _pxPerUnitAtScale1 * _districtScale,
    pairX: 0.7,
    clusterX: -0.9,
    y: 0.7,
  ),
];

Finder _rings() => find.byKey(const ValueKey('constellation.nodeRings'));

/// A field of only the people under test, pinned at known gaps (in anchor
/// units, from the pixel gaps this viewport settles on): no other node may
/// compete for the points tapped.
ConstellationField _fieldFor(_Viewport viewport) {
  final base = syntheticConstellationField(size: _everyone.length);
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
  final pairUnits = _pairGapPx / viewport.pxPerUnit;
  final clusterUnits = _clusterGapPx / viewport.pxPerUnit;
  return base.copyWith(
    requests: const [],
    anchorProjection: ConstellationAnchorProjection(
      revision: projection.revision,
      anchors: [
        pin(_pair[0], viewport.pairX, viewport.y),
        pin(_pair[1], viewport.pairX + pairUnits, viewport.y),
        for (var i = 0; i < _cluster.length; i++)
          pin(_cluster[i], viewport.clusterX + i * clusterUnits, viewport.y),
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

/// A click the way an accessibility client or a browser's semantics layer
/// delivers it: a tap action on whatever the semantics tree puts at [global].
void clickThroughSemantics(WidgetTester tester, Offset global) {
  tester.binding.renderViews.first.owner!.semanticsOwner!.performActionAt(
    global * tester.view.devicePixelRatio,
    SemanticsAction.tap,
  );
}

void main() {
  late ConstellationCubit cubit;
  late ConstellationPresentationFrameHolder holder;
  late Offset origin;

  Future<void> mountAtDetail(
    WidgetTester tester,
    _Viewport viewport,
  ) async {
    cubit = await loadReferenceCubit(field: _fieldFor(viewport));
    addTearDown(cubit.close);
    holder = ConstellationPresentationFrameHolder();
    await pumpConstellationBody(
      tester,
      cubit,
      size: viewport.size,
      locale: const Locale('en'),
      presentationFrameHolder: holder,
    );
    await tester.pumpAndSettle();
    final controller = cubit.graphController;
    for (var i = 0; i < 80; i++) {
      final target = viewport.scale;
      if (target == null) {
        controller.zoomBy(0.9);
      } else {
        if ((controller.cameraScale - target).abs() < 0.005) break;
        controller.zoomBy(target / controller.cameraScale);
      }
      await tester.pump();
    }
    await tester.pumpAndSettle();
    origin = tester.getTopLeft(find.byType(ConstellationViewportOverlay));

    final frame = holder.frame!;
    expect(frame.detail, viewport.detail);
    expect(
      (frame.bodies['fp:${_pair[0]}']!.center -
              frame.bodies['fp:${_pair[1]}']!.center)
          .distance,
      closeTo(_pairGapPx, 2),
      reason: 'the pair sits about $_pairGapPx px apart',
    );
    for (final MapEntry(:key, :value) in frame.bodies.entries) {
      if (_everyone.contains(key.substring(3))) continue;
      for (final id in _everyone) {
        expect(
          (value.center - frame.bodies['fp:$id']!.center).distance,
          greaterThan(kMinInteractiveDimension + 2),
          reason: '$key is clear of the dots under test ($id)',
        );
      }
    }
    for (var i = 0; i + 1 < _cluster.length; i++) {
      expect(
        (frame.bodies['fp:${_cluster[i]}']!.center -
                frame.bodies['fp:${_cluster[i + 1]}']!.center)
            .distance,
        closeTo(_clusterGapPx, 1.5),
        reason: 'the cluster dots sit about $_clusterGapPx px apart',
      );
    }
  }

  /// Settles the map with nothing selected and returns its current frame.
  Future<ConstellationPresentationFrame> freshFrame(WidgetTester tester) async {
    cubit.selectPerson(null);
    await tester.pumpAndSettle();
    return holder.frame!;
  }

  /// The segments between neighbouring dots, as (from, to) person ids.
  final segments = <(String, String)>[
    (_pair[0], _pair[1]),
    for (var i = 0; i + 1 < _cluster.length; i++)
      (_cluster[i], _cluster[i + 1]),
  ];

  /// Fractions along a segment, off the exact middle where two centres tie.
  const fractions = [0.1, 0.2, 0.35, 0.65, 0.8, 0.9];

  for (final viewport in _viewports) {
    group('overlapping round targets on the ${viewport.name} map', () {
      testWidgets('tapping the exact centre of each dot selects that dot', (
        tester,
      ) async {
        await mountAtDetail(tester, viewport);
        for (final id in _everyone) {
          final frame = await freshFrame(tester);
          await tester.tapAt(origin + frame.bodies['fp:$id']!.center);
          await tester.pumpAndSettle();

          expect(cubit.state.selectedPersonId, id, reason: 'tap on $id');
        }
      });

      testWidgets('the hover ring and a click choose the same node at points '
          'between two dots', (tester) async {
        await mountAtDetail(tester, viewport);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: origin);
        addTearDown(mouse.removePointer);

        for (final (from, to) in segments) {
          for (final t in fractions) {
            final frame = await freshFrame(tester);
            final a = frame.bodies['fp:$from']!.center;
            final b = frame.bodies['fp:$to']!.center;
            final p = a + (b - a) * t;
            await mouse.moveTo(origin + p);
            await tester.pump();
            final painter =
                tester.widget<CustomPaint>(_rings()).painter!
                    as ConstellationNodeRingPainter;
            final hovered = painter.hoveredGraphId;
            final nearest = t < 0.5 ? from : to;

            await mouse.down(origin + p);
            await mouse.up();
            await tester.pumpAndSettle();

            expect(
              hovered,
              'fp:$nearest',
              reason: 'hover at t=$t from $from to $to',
            );
            expect(
              cubit.state.selectedPersonId,
              nearest,
              reason: 'click at t=$t from $from to $to',
            );
          }
        }
      });

      testWidgets('a click delivered through semantics on the exact centre of '
          'each dot selects that dot', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await mountAtDetail(tester, viewport);
          for (final id in _everyone) {
            final frame = await freshFrame(tester);
            clickThroughSemantics(
              tester,
              origin + frame.bodies['fp:$id']!.center,
            );
            await tester.pumpAndSettle();

            expect(
              cubit.state.selectedPersonId,
              id,
              reason: 'semantics click on the centre of $id',
            );
          }
        } finally {
          handle.dispose();
        }
      });

      testWidgets('a click delivered through semantics between two dots '
          'selects the node the hover ring is on', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await mountAtDetail(tester, viewport);
          for (final (from, to) in segments) {
            for (final t in fractions) {
              final frame = await freshFrame(tester);
              final a = frame.bodies['fp:$from']!.center;
              final b = frame.bodies['fp:$to']!.center;
              final p = a + (b - a) * t;
              final hovered = resolveConstellationTap(frame, p);
              clickThroughSemantics(tester, origin + p);
              await tester.pumpAndSettle();

              expect(
                'fp:${cubit.state.selectedPersonId}',
                hovered,
                reason: 'semantics click at t=$t from $from to $to',
              );
            }
          }
        } finally {
          handle.dispose();
        }
      });
    });
  }
}
