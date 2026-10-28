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

// On a phone at the minimum zoom a finger must select the dot whose centre is
// nearest to where it lands, exactly as a mouse click there does. The cluster
// is laid out in screen px: two dots that overlap 2.5 px apart, a third about
// 4 px from them, three dots around a gap, and a dot about 10 px from its
// nearest neighbour.
//
// Two deliveries of the same taps:
//
// * Pointer events: real touch / mouse down-up events straight to the
//   framework, through the map's camera transform.
// * The web build in Chrome with semantics on (the dev build turns them on),
//   where every map dot is a `flt-tappable` DOM element the size of its
//   semantics rect. The engine's `ClickDebouncer` (flutter_web_sdk
//   pointer_binding.dart) holds a pointerdown that lands on a `flt-tappable`
//   element and, when the browser's click follows, sends the app a tap action
//   on the clicked element's node instead of the pointer events; a pointerdown
//   on no such element reaches the map as pointer events. A mouse lands on
//   the element under the cursor. A finger's pointerdown and click are both
//   moved by Chrome's touch adjustment onto the clickable element that best
//   fills the touch area around it, even when no element is under the finger.
//   [_chromeTouchAdjustedTarget] models that step. It was checked against
//   headless Chrome 2026-10 (CDP touch emulation, DPR 2, the semantics rects
//   this cluster lays out replayed as divs with click listeners): it named
//   the element Chrome dispatched pointerdown and click to for all 8 dot
//   centres and 11 points between and around them.

const _phone = Size(375, 667);
const _devicePixelRatio = 2.0;

/// Screen pixels per anchor unit on the phone's zoom floor.
const _pxPerUnit = 25.5;

/// Dot centres in screen px at the zoom floor, relative to the first dot.
const _cluster = <String, Offset>{
  'a1': Offset.zero,
  // Overlaps a1: 2.5 px apart.
  'a2': Offset(2.5, 0),
  // 4.3 px from a2.
  'b': Offset(5, 3.5),
  // About 10 px from its nearest neighbour (g).
  'c': Offset(12.5, -5),
  'd': Offset(-6, 3),
  // Around the gap at (0, -9): 6.5, 4.5 and 3.3 px from it.
  'e': Offset(0, -15.5),
  'f': Offset(-4.5, -9),
  'g': Offset(3.3, -9),
};

/// Largest gap (px) allowed between a dot's laid-out offset from a1 and its
/// offset in [_cluster].
const _layoutTolerancePx = 0.25;

/// Tap points between dots, in [_cluster] px, each with the dot nearest to it
/// (at least 1.2 px nearer than the runner-up) and its distances.
const _betweenDots = <(String, Offset, String)>[
  ('3.3 px from g, 4.5 px from f, 6.5 px from e', Offset(0, -9), 'g'),
  ('0.8 px from a2, 3.3 px from a1, 3.8 px from b', Offset(3.3, 0), 'a2'),
  ('1.6 px from a2, 2.8 px from b, 3.4 px from a1', Offset(3, 1.5), 'a2'),
  (
    '2.1 px from b, 3.4 px from a2, 5.7 px from a1',
    Offset(5.5, 1.5),
    'b',
  ),
  (
    '0.7 px from a1, 3.0 px from a2, 6.0 px from d',
    Offset(-0.5, 0.5),
    'a1',
  ),
  (
    '2.6 px from d, 4.3 px from a1, 6.5 px from a2',
    Offset(-3.5, 2.5),
    'd',
  ),
  ('2.8 px from f, 5.2 px from e, 6.1 px from g', Offset(-2.5, -11), 'f'),
  ('2.7 px from e, 5.3 px from f, 5.9 px from g', Offset(-1, -13), 'e'),
  ('4.0 px from c, 6.6 px from g, 7.8 px from a2', Offset(8.5, -5), 'c'),
];

ConstellationField _clusterField() {
  final base = syntheticConstellationField(size: _cluster.length);
  final projection = base.anchorProjection!;
  final ids = [for (var i = 0; i < _cluster.length; i++) 'p$i'];
  final offsets = _cluster.values.toList();
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
      anchors: [for (var i = 0; i < ids.length; i++) pin(ids[i], offsets[i])],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

/// Person id of the cluster dot named [name] in [_cluster].
String _idOf(String name) => 'p${_cluster.keys.toList().indexOf(name)}';

/// Cluster dot name of the person [id], or [id] itself when not a dot.
String _nameOf(String? id) {
  if (id == null) {
    return 'nothing';
  }
  final names = _cluster.keys.toList();
  final i = int.tryParse(id.substring(1));
  return i == null || i >= names.length ? id : names[i];
}

SemanticsOwner _semanticsOwner(WidgetTester tester) =>
    tester.binding.renderViews.single.owner!.semanticsOwner!;

/// The semantics nodes that offer a tap, each with its rect in global
/// logical px: on the web build each is a `flt-tappable` DOM element of that
/// rect, which the browser treats as a clickable element.
List<(int, Rect)> _tappableSemanticsRects(WidgetTester tester) {
  final found = <(int, Rect)>[];
  void visit(SemanticsNode node, Matrix4 parentToGlobal) {
    final toGlobal = node.transform == null
        ? parentToGlobal
        : parentToGlobal.multiplied(node.transform!);
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      found.add((
        node.id,
        MatrixUtils.transformRect(toGlobal, node.rect),
      ));
    }
    node.visitChildren((child) {
      visit(child, toGlobal);
      return true;
    });
  }

  final dpr = tester.view.devicePixelRatio;
  visit(
    _semanticsOwner(tester).rootSemanticsNode!,
    Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1),
  );
  return found;
}

/// Side (CSS px) of the smallest touch area Chrome adjusts a touch over
/// (`kMinAdjustmentSizeDip`); DevTools touch emulation never goes below it.
const _chromeMinTouchArea = 20.0;

/// The clickable element Chrome's touch adjustment sends a finger tap at
/// [touch] to, among [candidates] (global px), or null when the touch area
/// meets none of them. Mirrors Blink's `FindNodeWithLowestDistanceMetric`
/// with `HybridDistanceFunction`: integer root-frame geometry, a square touch
/// area around the rounded hotspot, the lowest score wins and an equal score
/// keeps the earlier candidate.
int? _chromeTouchAdjustedTarget(List<(int, Rect)> candidates, Offset touch) {
  final hotspot = Offset(
    touch.dx.roundToDouble(),
    touch.dy.roundToDouble(),
  );
  final area = Rect.fromCenter(
    center: hotspot,
    width: _chromeMinTouchArea,
    height: _chromeMinTouchArea,
  );
  final radiusSquared =
      0.25 * (area.width * area.width + area.height * area.height);
  int? best;
  var bestScore = double.infinity;
  for (final (id, raw) in candidates) {
    final rect = Rect.fromLTRB(
      raw.left.floorToDouble(),
      raw.top.floorToDouble(),
      raw.right.ceilToDouble(),
      raw.bottom.ceilToDouble(),
    );
    if (!rect.overlaps(area)) {
      continue;
    }
    final closest = Offset(
      hotspot.dx.clamp(rect.left, rect.right),
      hotspot.dy.clamp(rect.top, rect.bottom),
    );
    final distanceScore = (closest - hotspot).distanceSquared / radiusSquared;
    final maxOverlap = [
      (rect.width < area.width ? rect.width : area.width) *
          (rect.height < area.height ? rect.height : area.height),
      1.0,
    ].reduce((a, b) => a > b ? a : b);
    final overlap = rect.intersect(area);
    final intersectionScore = 1 - overlap.width * overlap.height / maxOverlap;
    final score = intersectionScore + distanceScore;
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
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

/// Whether some semantics node offering a tap covers [global] (logical px):
/// a mouse click there lands on a `flt-tappable` element. Descends the tree
/// the way [SemanticsOwner.performActionAt] does, so both agree on rect
/// edges.
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

/// A tap at [global] delivered the way Chrome and the Flutter web engine
/// deliver it with semantics on.
///
/// A press that lands on a tappable element becomes a tap action on that
/// element's node; any other press reaches the map as pointer events. A mouse
/// lands on the element under the cursor (the one the semantics tree hit test
/// finds there); a finger lands on the one Chrome's touch adjustment picks.
Future<void> _tapAsTheBrowserDelivers(
  WidgetTester tester,
  PointerDeviceKind kind,
  Offset global,
) async {
  final owner = _semanticsOwner(tester);
  if (kind == PointerDeviceKind.touch) {
    final target = _chromeTouchAdjustedTarget(
      _tappableSemanticsRects(tester),
      global,
    );
    if (target == null) {
      await _pointerTap(tester, kind, global);
      return;
    }
    owner.performAction(target, SemanticsAction.tap);
  } else {
    if (!_tappableSemanticsCovers(tester, global)) {
      await _pointerTap(tester, kind, global);
      return;
    }
    owner.performActionAt(
      global * tester.view.devicePixelRatio,
      SemanticsAction.tap,
    );
  }
  await tester.pumpAndSettle();
}

typedef _Delivery = ({
  bool semantics,
  Future<void> Function(WidgetTester, PointerDeviceKind, Offset) tap,
});

const _deliveries = <String, _Delivery>{
  'as the web build in Chrome delivers it with semantics on': (
    semantics: true,
    tap: _tapAsTheBrowserDelivers,
  ),
  'as pointer events through the map camera': (
    semantics: false,
    tap: _pointerTap,
  ),
};

void main() {
  late ConstellationCubit cubit;
  late ConstellationPresentationFrameHolder holder;
  late Offset origin;

  Offset centreOf(String name) =>
      holder.frame!.bodies['fp:${_idOf(name)}']!.center;

  /// A point given in [_cluster] px, on the current frame.
  Offset onFrame(Offset clusterPx) => centreOf('a1') + clusterPx;

  Future<void> mountAtMinimumZoom(WidgetTester tester) async {
    tester.view.devicePixelRatio = _devicePixelRatio;
    addTearDown(tester.view.resetDevicePixelRatio);
    cubit = await loadReferenceCubit(field: _clusterField());
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
    expect(holder.frame!.detail, ConstellationDetailLevel.overview);
    // The expected dots below are worked out from [_cluster]; they hold only
    // if the map lays the dots out at those screen offsets.
    final drift = <String>[
      for (final MapEntry(key: name, value: designed) in _cluster.entries)
        if ((centreOf(name) - centreOf('a1') - designed).distance >
            _layoutTolerancePx)
          '$name at ${centreOf(name) - centreOf('a1')}, designed $designed',
    ];
    expect(drift, isEmpty, reason: 'the map lays the cluster out as designed');
  }

  Future<void> withSemantics(
    WidgetTester tester, {
    required bool semantics,
    required Future<void> Function() body,
  }) async {
    final handle = semantics ? tester.ensureSemantics() : null;
    try {
      await body();
    } finally {
      handle?.dispose();
    }
  }

  /// Clears the selection, then taps at [at] (viewport px) as read off the
  /// settled frame, and returns the cluster dot the tap selected. Selecting a
  /// dot pans the camera, so every point is read again right before its tap.
  Future<String> tapAndRead(
    WidgetTester tester,
    _Delivery delivery,
    PointerDeviceKind kind,
    Offset Function() at,
  ) async {
    cubit.selectPerson(null);
    await tester.pumpAndSettle();
    await delivery.tap(tester, kind, origin + at());
    return _nameOf(cubit.state.selectedPersonId);
  }

  for (final MapEntry(key: deliveryName, value: delivery)
      in _deliveries.entries) {
    group('a dense cluster on a phone at the minimum zoom, $deliveryName', () {
      testWidgets(
        'a touch tap on the centre of each dot selects that dot',
        (tester) async => withSemantics(
          tester,
          semantics: delivery.semantics,
          body: () async {
            await mountAtMinimumZoom(tester);
            final misses = <String>[];
            for (final name in _cluster.keys) {
              final selected = await tapAndRead(
                tester,
                delivery,
                PointerDeviceKind.touch,
                () => centreOf(name),
              );
              if (selected != name) {
                misses.add('touch on the centre of $name selected $selected');
              }
            }
            expect(misses, isEmpty);
          },
        ),
      );

      testWidgets(
        'a touch tap between dots selects the nearest one',
        (tester) async => withSemantics(
          tester,
          semantics: delivery.semantics,
          body: () async {
            await mountAtMinimumZoom(tester);
            final misses = <String>[];
            for (final (label, at, nearest) in _betweenDots) {
              final selected = await tapAndRead(
                tester,
                delivery,
                PointerDeviceKind.touch,
                () => onFrame(at),
              );
              if (selected != nearest) {
                misses.add('$label: selected $selected');
              }
            }
            expect(misses, isEmpty);
          },
        ),
      );

      testWidgets(
        'touch and mouse select the same dot at every tap point',
        (tester) async => withSemantics(
          tester,
          semantics: delivery.semantics,
          body: () async {
            await mountAtMinimumZoom(tester);
            final points = <(String, Offset, String)>[
              for (final MapEntry(key: name, value: at) in _cluster.entries)
                ('centre of $name', at, name),
              ..._betweenDots,
            ];
            final differences = <String>[];
            for (final (label, at, nearest) in points) {
              final byTouch = await tapAndRead(
                tester,
                delivery,
                PointerDeviceKind.touch,
                () => onFrame(at),
              );
              final byMouse = await tapAndRead(
                tester,
                delivery,
                PointerDeviceKind.mouse,
                () => onFrame(at),
              );
              if (byMouse != nearest || byTouch != byMouse) {
                differences.add(
                  '$label: touch $byTouch, mouse $byMouse, nearest $nearest',
                );
              }
            }
            expect(differences, isEmpty);
          },
        ),
      );
    });
  }
}
