import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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

// #640: on a phone at the minimum zoom the dots of a dense people cluster sit
// 3–9 px apart in two dimensions. Every dot must be selectable by tapping its
// centre, and a tap between dots must select the dot whose centre is nearest.
//
// The dev web build runs with semantics on (`App`'s startup
// `ensureSemantics()`). The web engine then delivers a tap that lands on a
// tappable semantics element as `SemanticsAction.tap` on that node, and the
// pointer events never reach the framework (its click debouncer drops them);
// only a tap that lands on no tappable semantics element reaches the map as
// pointer events. So the semantics tree, not the map's pointer hit test,
// decides what a real finger selects there. [_tapAsTheWebEngineDelivers]
// reproduces that delivery; the pointer tests send the same taps as real
// touch / mouse down-up events straight to the framework.

const _phone = Size(375, 667);
const _devicePixelRatio = 2.0;

/// Screen pixels per anchor unit on the phone's zoom floor.
const _pxPerUnit = 25.5;

/// Dense clusters shaped like the one QA found failing: seven dots around a
/// point, offsets in screen px at the zoom floor.
const _clusters = <String, List<Offset>>{
  '5–9 px apart': [
    Offset.zero,
    Offset(5, 2),
    Offset(2, 7),
    Offset(-4, 5),
    Offset(-7, -1),
    Offset(-2, -6),
    Offset(6, -5),
  ],
  '3–5 px apart': [
    Offset.zero,
    Offset(3, 1),
    Offset(1, 4),
    Offset(-3, 3),
    Offset(-4, -1),
    Offset(-1, -4),
    Offset(4, -3),
  ],
};

/// Fractions along the segment between two dots.
const _fractions = [0.25, 0.4, 0.6, 0.75];

/// A point this close (px) to being equidistant from two centres is a tie and
/// is not asked about.
const _tieMarginPx = 0.75;

ConstellationField _clusterField(List<Offset> offsetsPx) {
  final base = syntheticConstellationField(size: offsetsPx.length);
  final projection = base.anchorProjection!;
  ConstellationAnchor pin(String id, Offset px) => ConstellationAnchor(
    target: ConstellationAnchorTarget.person(id),
    position: ConstellationAnchorPosition(
      xUnits: -2 + px.dx / _pxPerUnit,
      yUnits: 2 + px.dy / _pxPerUnit,
      coordinateSpaceVersion: 1,
    ),
    revision: projection.revision,
    placedAt: base.loadedAt,
  );
  return base.copyWith(
    requests: const [],
    anchorProjection: ConstellationAnchorProjection(
      revision: projection.revision,
      anchors: [
        for (var i = 0; i < offsetsPx.length; i++) pin('p$i', offsetsPx[i]),
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

SemanticsOwner _semanticsOwner(WidgetTester tester) =>
    tester.binding.renderViews.single.owner!.semanticsOwner!;

/// Whether some semantics node offering a tap covers [global] (logical px):
/// on the web build with semantics on such a tap reaches the app as a
/// semantics action and never as pointer events. Descends the tree the way
/// [SemanticsOwner.performActionAt] does, so both agree on rect edges.
bool _tappableSemanticsCovers(WidgetTester tester, Offset global) {
  bool covers(SemanticsNode node, Offset inParent) {
    var position = inParent;
    final transform = node.transform;
    if (transform != null) {
      final inverse = Matrix4.tryInvert(transform);
      if (inverse == null) {
        return false;
      }
      position = MatrixUtils.transformPoint(inverse, inParent);
    }
    if (!node.rect.contains(position)) {
      return false;
    }
    var covered = node.getSemanticsData().hasAction(SemanticsAction.tap);
    node.visitChildren((child) {
      covered = covers(child, position) || covered;
      return !covered;
    });
    return covered;
  }

  return covers(
    _semanticsOwner(tester).rootSemanticsNode!,
    global * tester.view.devicePixelRatio,
  );
}

/// A real pointer tap at [global]: down and up of one [kind] pointer, through
/// the gesture arena the map's recognizers compete in.
Future<void> _pointerTap(
  WidgetTester tester,
  PointerDeviceKind kind,
  Offset global,
) async {
  final gesture = await tester.createGesture(kind: kind);
  if (kind == PointerDeviceKind.mouse) {
    await gesture.addPointer(location: global);
  }
  await gesture.down(global);
  await gesture.up();
  if (kind == PointerDeviceKind.mouse) {
    await gesture.removePointer();
  }
  await tester.pumpAndSettle();
}

/// Taps [_tapAsTheWebEngineDelivers] handed to the semantics tree as a tap
/// action, in the current test.
var _semanticsTaps = 0;

/// A tap at [global] delivered the way the web engine delivers it with
/// semantics on: a tap action on whatever the semantics tree puts there when
/// a tappable semantics node covers it, or else the pointer events themselves
/// (the engine forwards a pointerdown on a non-tappable element at once).
Future<void> _tapAsTheWebEngineDelivers(
  WidgetTester tester,
  PointerDeviceKind kind,
  Offset global,
) async {
  if (!_tappableSemanticsCovers(tester, global)) {
    await _pointerTap(tester, kind, global);
    return;
  }
  _semanticsTaps++;
  _semanticsOwner(tester).performActionAt(
    global * tester.view.devicePixelRatio,
    SemanticsAction.tap,
  );
  await tester.pumpAndSettle();
}

typedef _Delivery = ({
  bool semantics,
  Future<void> Function(WidgetTester, PointerDeviceKind, Offset) tap,
});

const _deliveries = <String, _Delivery>{
  'on the web build with semantics on': (
    semantics: true,
    tap: _tapAsTheWebEngineDelivers,
  ),
  'with pointer events straight to the map': (
    semantics: false,
    tap: _pointerTap,
  ),
};

void main() {
  late ConstellationCubit cubit;
  late ConstellationPresentationFrameHolder holder;
  late Offset origin;
  late List<String> ids;

  Future<void> mountAtMinimumZoom(
    WidgetTester tester,
    List<Offset> offsetsPx, {
    required bool semantics,
  }) async {
    tester.view.devicePixelRatio = _devicePixelRatio;
    addTearDown(tester.view.resetDevicePixelRatio);
    ids = [for (var i = 0; i < offsetsPx.length; i++) 'p$i'];
    cubit = await loadReferenceCubit(field: _clusterField(offsetsPx));
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
    for (final id in ids) {
      final centre = frame.bodies['fp:$id']!.center;
      final nearest = [
        for (final other in ids)
          if (other != id)
            (frame.bodies['fp:$other']!.center - centre).distance,
      ].reduce((a, b) => a < b ? a : b);
      expect(
        nearest,
        inInclusiveRange(2.5, 9.5),
        reason: 'the dot of $id sits 3–9 px from its nearest neighbour',
      );
    }
    if (semantics) {
      expect(
        _semanticsOwner(tester).rootSemanticsNode,
        isNotNull,
        reason: 'semantics are on, as on the dev web build',
      );
    }
  }

  /// Runs [body] with semantics on when [semantics], as the dev web build
  /// does; the handle must be released inside the test body.
  Future<void> withSemantics(
    WidgetTester tester, {
    required bool semantics,
    required Future<void> Function() body,
  }) async {
    final handle = semantics ? tester.ensureSemantics() : null;
    _semanticsTaps = 0;
    try {
      await body();
    } finally {
      handle?.dispose();
    }
  }

  /// The cluster dot whose centre is nearest to [p] (viewport px) on [frame],
  /// or null when the two nearest centres are within [_tieMarginPx].
  String? nearestDot(ConstellationPresentationFrame frame, Offset p) {
    final byDistance = [
      for (final id in ids) (id, (frame.bodies['fp:$id']!.center - p).distance),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (byDistance[1].$2 - byDistance[0].$2 < _tieMarginPx) {
      return null;
    }
    return byDistance[0].$1;
  }

  for (final MapEntry(key: clusterName, value: offsetsPx)
      in _clusters.entries) {
    for (final MapEntry(key: deliveryName, value: delivery)
        in _deliveries.entries) {
      group('a dense cluster of dots $clusterName on a phone at the minimum '
          'zoom, $deliveryName', () {
        for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
          testWidgets(
            'a ${kind.name} tap on the exact centre of each dot '
            'selects that dot, the panel left open between taps',
            (
              tester,
            ) async => withSemantics(
              tester,
              semantics: delivery.semantics,
              body: () async {
                await mountAtMinimumZoom(
                  tester,
                  offsetsPx,
                  semantics: delivery.semantics,
                );
                final misses = <String>[];
                for (var round = 0; round < 2; round++) {
                  for (final id in ids) {
                    final frame = holder.frame!;
                    await delivery.tap(
                      tester,
                      kind,
                      origin + frame.bodies['fp:$id']!.center,
                    );
                    final selected = cubit.state.selectedPersonId;
                    if (selected != id) {
                      misses.add('tap on $id selected $selected');
                    }
                  }
                }

                expect(misses, isEmpty);
                if (delivery.semantics) {
                  expect(
                    _semanticsTaps,
                    2 * ids.length,
                    reason:
                        'every dot centre is covered by a tappable '
                        'semantics node',
                  );
                }
              },
            ),
          );

          testWidgets(
            'a ${kind.name} tap between two dots selects the dot '
            'whose centre is nearest',
            (tester) async => withSemantics(
              tester,
              semantics: delivery.semantics,
              body: () async {
                await mountAtMinimumZoom(
                  tester,
                  offsetsPx,
                  semantics: delivery.semantics,
                );
                final misses = <String>[];
                var asked = 0;
                for (var i = 0; i < ids.length; i++) {
                  for (var j = i + 1; j < ids.length; j++) {
                    for (final t in _fractions) {
                      cubit.selectPerson(null);
                      await tester.pumpAndSettle();
                      final frame = holder.frame!;
                      final a = frame.bodies['fp:${ids[i]}']!.center;
                      final b = frame.bodies['fp:${ids[j]}']!.center;
                      final p = a + (b - a) * t;
                      final expected = nearestDot(frame, p);
                      if (expected == null) {
                        continue;
                      }
                      asked++;
                      await delivery.tap(tester, kind, origin + p);
                      final selected = cubit.state.selectedPersonId;
                      if (selected != expected) {
                        misses.add(
                          'tap at t=$t from ${ids[i]} to ${ids[j]} selected '
                          '$selected, nearest is $expected',
                        );
                      }
                    }
                  }
                }

                expect(
                  asked,
                  greaterThan(40),
                  reason: 'most points are no tie',
                );
                expect(misses, isEmpty);
                if (delivery.semantics) {
                  expect(
                    _semanticsTaps,
                    greaterThan(asked ~/ 4),
                    reason: "many taps land on the dots' semantics nodes",
                  );
                }
              },
            ),
          );
        }
      });
    }
  }
}
