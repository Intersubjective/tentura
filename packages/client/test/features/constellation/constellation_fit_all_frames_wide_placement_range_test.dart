// «Show whole field» (fit-all) frames nodes placed anywhere in the widened
// placement range (±kConstellationCoordinateMaxUnits), and the Field canvas
// lets the camera zoom out as far as that fit needs.
//
// Every Field comes from a real server response mapped by the real
// ConstellationRepository into a real store and ConstellationCubit, drawn by
// the real ConstellationBody; fit-all is tapped through its on-screen control.
// Bodies are checked in camera maths (scene body rect through the live camera
// into viewport pixels).
//
// Evidence scope: the pinch and wheel zoom-out tests drive simulated pointer
// events in a widget test. Touch and scroll behaviour is only proven by the
// web integration_test (scripts/run_client_integration_web_local.sh) or
// Playwright, which this file does not replace; those two claims are
// widget-level only. (Flutter's InteractiveViewer treats a positive scroll dy
// as zoom out.)
@TestOn('vm')
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'bob', displayName: 'Боб');
const _phone = kPhoneSurface;
const _desktop = Size(1280, 800);
const _cap = kConstellationCoordinateMaxUnits;
const _unit = kConstellationRingUnitPixels;
const _fitPadding = 48.0;

typedef _Units = Map<String, (double, double)>;

Map<String, dynamic> _peer(String id, String name) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'contactOnly': false,
  'displayName': name,
  'handle': null,
  'image': null,
  'isNew': false,
  'pinState': null,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'visible': true,
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
};

Map<String, dynamic> _anchor(String id, double x, double y) => {
  '__typename': 'v2_ConstellationAnchor',
  'targetKind': 'PERSON',
  'targetId': id,
  'xUnits': x,
  'yUnits': y,
  'coordinateSpaceVersion': 1,
  'revision': '1',
  'placedAt': '2026-11-08T12:00:00.000Z',
};

/// Bob at the centre plus anchored direct contacts at [people] (units).
Map<String, dynamic> _fieldResponse(_Units people) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-08T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [...people.keys],
    'peers': [
      _peer(_viewer.id, _viewer.displayName),
      for (final id in people.keys) _peer(id, 'Гость $id'),
    ],
    'edges': [
      for (final id in people.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': _viewer.id,
          'dst': id,
          'tier': 1,
        },
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '1',
      'anchors': [
        _anchor(_viewer.id, 0, 0),
        for (final e in people.entries) _anchor(e.key, e.value.$1, e.value.$2),
      ],
      'pinnedPeers': [
        for (final id in people.keys) _peer(id, 'Гость $id'),
      ],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

final class _ServerField implements ConstellationRepositoryPort {
  _ServerField(this.field);
  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

final _openCubits = <ConstellationCubit>[];

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A Field test that leaves no Field running behind it. Mounts [people] on
/// [surface] and hands the cubit to [body].
void _fieldTest(
  String description,
  Size surface,
  _Units people,
  Future<void> Function(WidgetTester tester, ConstellationCubit cubit) body,
) => testWidgets(description, (tester) async {
  try {
    late final ConstellationField field;
    await withRemoteWire(
      {'ConstellationFieldFetch': _fieldResponse(people)},
      [],
      (remote) async {
        field = await ConstellationRepository(remote).fetch();
      },
    );
    final store = ConstellationStoreFixture(
      _ServerField(field),
      accountId: _viewer.id,
    );
    final cubit = store.createCubit(viewer: _viewer);
    unawaited(cubit.load());
    await tester.runAsync(
      () => cubit.stream
          .firstWhere((s) => s.status is StateIsSuccess)
          .timeout(const Duration(seconds: 10)),
    );
    _openCubits.add(cubit);
    await pumpConstellationBody(tester, cubit, size: surface);
    await _pumpFrames(tester, 60);
    await body(tester, cubit);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    for (final cubit in _openCubits) {
      if (!cubit.isClosed) await cubit.close();
    }
    _openCubits.clear();
    await _pumpFrames(tester, 2);
  }
});

/// The viewport minus the insets the Field frames its camera into.
Rect _safeRect(ConstellationCubit cubit) {
  final size = cubit.graphController.viewportSize!;
  return cubit.fieldCameraViewportSnapshotForTest.deflateRect(
    Offset.zero & size,
  );
}

Offset _scenePosition(ConstellationCubit cubit, String id) {
  final p = cubit.graphController.renderSnapshot.resolvePosition(id);
  expect(p, isNotNull, reason: '$id is placed');
  return Offset(p!.x, p.y);
}

Rect _sceneBody(ConstellationCubit cubit, String id) {
  final node = cubit.graphController.renderSnapshot.topology.nodesById[id]!;
  return Rect.fromCenter(
    center: _scenePosition(cubit, id),
    width: node.size.width,
    height: node.size.height,
  );
}

Rect _bodyOnScreen(ConstellationCubit cubit, String id) {
  final scene = _sceneBody(cubit, id);
  return Rect.fromPoints(
    cubit.graphController.sceneToViewportLocal(scene.topLeft),
    cubit.graphController.sceneToViewportLocal(scene.bottomRight),
  );
}

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

void _expectAllInView(
  ConstellationCubit cubit,
  Iterable<String> people, {
  required String when,
}) {
  final safe = _safeRect(cubit);
  for (final id in ['bob', ...people]) {
    final body = _bodyOnScreen(cubit, 'fp:$id');
    expect(
      _inside(safe, body),
      isTrue,
      reason:
          '$when: $id body $body lies inside the safe viewport $safe '
          '(camera scale ${cubit.graphController.cameraScale})',
    );
  }
}

Future<void> _tapFitAll(WidgetTester tester) async {
  final control = find.byKey(TestIds.key(TestIds.constellationFitAll));
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await _pumpFrames(tester, 30);
}

/// The Field canvas: the InteractiveViewer inside the Field's GraphView.
Finder get _fieldCanvas => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('GraphView<'),
  ),
  matching: find.byType(InteractiveViewer),
);

double _canvasMinScale(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(_fieldCanvas).minScale;

/// Scale that fits a ±[units] square of footprints into the safe viewport.
double _envelopeScale(Rect safe, double units) {
  final span = 2 * units * _unit + 2 * _fitPadding;
  return math.min(safe.width, safe.height) / span;
}

void main() {
  const sizes = {'phone 375x667': _phone, 'desktop 1280x800': _desktop};

  // Bob sits at the centre as well, so each layout also spans the centre.
  final layouts = <String, _Units>{
    'horizontal opposite sides': {
      'west': (-_cap, 0),
      'east': (_cap, 0),
    },
    'vertical opposite sides': {
      'north': (0, -_cap),
      'south': (0, _cap),
    },
    'opposite corners': {
      'nw': (-_cap, -_cap),
      'se': (_cap, _cap),
    },
  };

  group('Fit-all frames nodes placed at the placement cap', () {
    for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
      for (final MapEntry(key: layoutName, value: people) in layouts.entries) {
        _fieldTest(
          'on $sizeName, nodes at $layoutName all lie inside the viewport '
          'after one tap',
          size,
          people,
          (tester, cubit) async {
            await _tapFitAll(tester);
            expect(tester.takeException(), isNull);
            _expectAllInView(cubit, people.keys, when: 'after fit-all');
          },
        );
      }

      _fieldTest(
        'on $sizeName, a cluster plus one node dragged four viewport widths '
        'away all lie inside the viewport after one tap',
        size,
        {
          'c1': (1.5, 0),
          'c2': (-1.5, 1),
          'c3': (0, -2),
          'c4': (-1, 1.5),
          'far': (size.width * 4 / _unit, 0),
        },
        (tester, cubit) async {
          await _tapFitAll(tester);
          _expectAllInView(
            cubit,
            ['c1', 'c2', 'c3', 'c4', 'far'],
            when: 'after fit-all',
          );
        },
      );

      _fieldTest(
        'on $sizeName, the canvas minimum zoom allows the fit-all scale and '
        'the fitted camera stays put once the Field settles',
        size,
        layouts['opposite corners']!,
        (tester, cubit) async {
          await _tapFitAll(tester);
          final scale = cubit.graphController.cameraScale;
          final centre = cubit.graphController.viewportLocalToScene(
            _safeRect(cubit).center,
          );
          expect(
            _canvasMinScale(tester),
            lessThanOrEqualTo(scale + 1e-9),
            reason: 'the canvas minimum zoom is not above the fit-all scale',
          );

          await _pumpFrames(tester, 60);
          expect(
            cubit.graphController.cameraScale,
            closeTo(scale, 1e-4),
            reason: 'the camera scale does not move after settling',
          );
          expect(
            (cubit.graphController.viewportLocalToScene(
                      _safeRect(cubit).center,
                    ) -
                    centre)
                .distance,
            lessThanOrEqualTo(1),
            reason: 'the camera does not pan after settling',
          );
          _expectAllInView(cubit, ['nw', 'se'], when: 'after settling');
        },
      );

      _fieldTest(
        'on $sizeName, pinching the map out reaches the fit-all scale, which '
        'is the scale that frames both corners',
        size,
        layouts['opposite corners']!,
        (tester, cubit) async {
          await _tapFitAll(tester);
          final fitScale = cubit.graphController.cameraScale;
          // Zoom in so there is room to pinch out again.
          cubit.graphController.zoomBy(1 / fitScale);
          await _pumpFrames(tester, 10);
          final start = cubit.graphController.cameraScale;
          expect(start, greaterThan(fitScale * 2));

          final centre = tester.getCenter(_fieldCanvas);
          var previous = start;
          for (var round = 0; round < 12; round++) {
            final a = await tester.startGesture(centre - const Offset(120, 0));
            final b = await tester.startGesture(centre + const Offset(120, 0));
            await tester.pump();
            for (var i = 0; i < 6; i++) {
              await a.moveBy(const Offset(18, 0));
              await b.moveBy(const Offset(-18, 0));
              await tester.pump();
            }
            await a.up();
            await b.up();
            await _pumpFrames(tester, 5);
            final now = cubit.graphController.cameraScale;
            if (round == 0) {
              expect(
                now,
                lessThan(start),
                reason: 'the pinch gesture is recognised and zooms out',
              );
            }
            if ((now - previous).abs() < 1e-6) break;
            previous = now;
          }
          expect(
            cubit.graphController.cameraScale,
            lessThanOrEqualTo(fitScale * 1.01),
            reason: 'the pinch is not stopped above the fit-all scale',
          );
          // fit-all must really frame the ±cap corners (not sit at a clamp).
          final needed = _envelopeScale(_safeRect(cubit), _cap);
          expect(
            fitScale,
            lessThanOrEqualTo(needed * 1.05),
            reason: 'fit-all scale $fitScale frames the corners ($needed)',
          );
          _expectAllInView(cubit, ['nw', 'se'], when: 'after fit-all');
        },
      );

      _fieldTest(
        'on $sizeName, scrolling the wheel out reaches the fit-all scale',
        size,
        layouts['opposite corners']!,
        (tester, cubit) async {
          await _tapFitAll(tester);
          final fitScale = cubit.graphController.cameraScale;
          cubit.graphController.zoomBy(1 / fitScale);
          await _pumpFrames(tester, 10);
          final start = cubit.graphController.cameraScale;

          final centre = tester.getCenter(_fieldCanvas);
          final mouse = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(mouse.hover(centre));
          var previous = start;
          for (var i = 0; i < 40; i++) {
            await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
            await _pumpFrames(tester, 3);
            final now = cubit.graphController.cameraScale;
            if (i == 0) {
              expect(now, lessThan(start), reason: 'wheel zooms out');
            }
            if ((now - previous).abs() < 1e-6) break;
            previous = now;
          }
          expect(
            cubit.graphController.cameraScale,
            lessThanOrEqualTo(fitScale * 1.01),
            reason: 'wheel zoom-out is not stopped above the fit-all scale',
          );
          expect(
            fitScale,
            lessThanOrEqualTo(_envelopeScale(_safeRect(cubit), _cap) * 1.05),
            reason: 'fit-all scale $fitScale really frames the ±cap corners',
          );
        },
      );
    }
  });

  group('Fit-all follows the placed nodes, not the placement envelope', () {
    _fieldTest(
      'a small cluster is framed at the content fit, capped at 1, and '
      'centred on the nodes',
      _desktop,
      {
        'a': (2, 0),
        'b': (-2, 0),
        'c': (0, 2),
        'd': (0, -2),
      },
      (tester, cubit) async {
        await _tapFitAll(tester);
        final safe = _safeRect(cubit);
        final scale = cubit.graphController.cameraScale;
        expect(scale, lessThanOrEqualTo(1 + 1e-9));
        // Content fit: the placed bodies plus the 48 px fit padding into the
        // safe viewport, never above 1.
        final scene = [
          for (final id in ['bob', 'a', 'b', 'c', 'd'])
            _sceneBody(cubit, 'fp:$id'),
        ].reduce((x, y) => x.expandToInclude(y));
        final contentFit = math.min(
          1,
          math.min(
            safe.width / (scene.width + 2 * _fitPadding),
            safe.height / (scene.height + 2 * _fitPadding),
          ),
        );
        expect(
          scale,
          closeTo(contentFit, 1e-3),
          reason: 'fit-all scale equals the content fit capped at 1',
        );
        expect(
          scale,
          greaterThan(_envelopeScale(safe, _cap)),
          reason: 'not zoomed out to show the whole placement envelope',
        );
        _expectAllInView(cubit, ['a', 'b', 'c', 'd'], when: 'after fit-all');
        final bounds = [
          for (final id in ['bob', 'a', 'b', 'c', 'd'])
            _bodyOnScreen(cubit, 'fp:$id'),
        ].reduce((x, y) => x.expandToInclude(y));
        expect(
          (bounds.center - safe.center).distance,
          lessThanOrEqualTo(40),
          reason: 'the framed nodes are centred in the safe viewport',
        );
      },
    );
  });
}
