// Fields loaded from the server through the real repository mapping:
//
// * iPhone SE (375×667), RU: anchors spread past the old ±10 units, out to the
//   shared bound, render cleanly with labels, sit at their stored places, and
//   fit-all never zooms below the documented fit-all floor; when the layout
//   fits at that floor every node is on screen.
// * Default desktop viewport: a layout placed inside the old ±10 range keeps
//   its positions and ring radius, or else stays fully visible and no smaller
//   on screen than before.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/util/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/util/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

/// The widened bound shared with the server and the database CHECK.
const _bound = kConstellationCoordinateMaxUnits;

/// The documented fit-all floor: «Показать всё поле» never zooms out below it
/// (also pinned at 375 RU by the Field camera policy tests).
const _fitAllFloor = kConstellationDistrictDetailScale;

const _viewer = Profile(id: 'bob', displayName: 'Боб');

const _names = {
  'anna': 'Анна',
  'boris': 'Борис',
  'dima': 'Дима',
  'kira': 'Кира',
};

typedef _At = ({double x, double y});

Map<String, dynamic> _peer(String id, String displayName) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'contactOnly': false,
  'displayName': displayName,
  'handle': null,
  'image': null,
  'isNew': false,
  'pinState': null,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'visible': true,
};

/// Bob's Field as the server sends it: four direct contacts, the ones in
/// [anchored] pinned there.
Map<String, dynamic> _fieldResponse(Map<String, _At> anchored) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-06T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': _names.keys.toList(),
    'peers': [
      _peer('bob', 'Боб'),
      for (final MapEntry(:key, :value) in _names.entries) _peer(key, value),
    ],
    'edges': [
      for (final dst in _names.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': 'bob',
          'dst': dst,
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
        for (final MapEntry(:key, :value) in anchored.entries)
          {
            '__typename': 'v2_ConstellationAnchor',
            'targetKind': 'PERSON',
            'targetId': key,
            'xUnits': value.x,
            'yUnits': value.y,
            'coordinateSpaceVersion': 1,
            'revision': '1',
            'placedAt': '2026-11-06T12:00:00.000Z',
          },
      ],
      'pinnedPeers': [
        for (final id in anchored.keys) _peer(id, _names[id]!),
      ],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

/// Loads [anchored] through the real repository mapping into a Field cubit.
Future<ConstellationCubit> _loadFromWire(Map<String, _At> anchored) async {
  late final ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': _fieldResponse(anchored)},
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(field),
    viewer: _viewer,
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

double _scenePixel(double units) =>
    kConstellationCanvasCentre + units * kConstellationRingUnitPixels;

Offset _sceneOf(ConstellationCubit cubit, String peerId) {
  final at = cubit.graphController.getPositionOrNullForId('fp:$peerId');
  expect(at, isNotNull, reason: '$peerId is laid out');
  return at!;
}

/// Where a scene point is drawn on screen, through the Field camera.
Offset _screenOf(WidgetTester tester, Offset scene) {
  final viewer = find.byType(InteractiveViewer);
  final matrix = tester
      .widget<InteractiveViewer>(viewer)
      .transformationController!
      .value;
  return tester.getTopLeft(viewer) + MatrixUtils.transformPoint(matrix, scene);
}

bool _onScreen(Offset point, Size viewport) =>
    point.dx >= 0 &&
    point.dy >= 0 &&
    point.dx <= viewport.width &&
    point.dy <= viewport.height;

Future<void> _tapFitAll(WidgetTester tester) async {
  await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
  await tester.pumpAndSettle();
}

/// Every person on Bob's Field: Bob himself and his four contacts.
final _everyone = ['bob', ..._names.keys];

/// After fit-all: never below the floor, and when every node fits on
/// [viewport] at the floor, every node is on screen.
void _expectFitAllFrames(
  WidgetTester tester,
  ConstellationCubit cubit,
  Size viewport,
) {
  final peerIds = _everyone;
  final scale = cubit.graphController.cameraScale;
  expect(scale, greaterThanOrEqualTo(_fitAllFloor - 1e-9));
  final scene = [for (final id in peerIds) _sceneOf(cubit, id)];
  final xs = scene.map((p) => p.dx);
  final ys = scene.map((p) => p.dy);
  final span = Size(
    xs.reduce(math.max) - xs.reduce(math.min),
    ys.reduce(math.max) - ys.reduce(math.min),
  );
  final fitsAtFloor =
      span.width * _fitAllFloor <= viewport.width &&
      span.height * _fitAllFloor <= viewport.height;
  if (!fitsAtFloor) return;
  for (final (i, id) in peerIds.indexed) {
    expect(
      _onScreen(_screenOf(tester, scene[i]), viewport),
      isTrue,
      reason: '$id must be on screen after fit-all at scale $scale',
    );
  }
}

void main() {
  group('Field spread past the old ±10 units on iPhone SE (RU)', () {
    const spread = {
      'anna': (x: 11.0, y: -11.0),
      'boris': (x: _bound, y: _bound),
      'dima': (x: -_bound, y: -_bound),
    };

    testWidgets(
      'renders in Russian without overflow, with the fit-all control and '
      'every contact label, each pinned node at its stored place',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadFromWire(spread);
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          Localizations.localeOf(
            tester.element(find.byType(ConstellationBody)),
          ).languageCode,
          'ru',
        );
        expect(
          find.byKey(TestIds.key(TestIds.constellationFitAll)),
          findsOneWidget,
        );
        for (final name in _names.values) {
          expect(
            find.text(name, skipOffstage: false),
            findsWidgets,
            reason: 'label «$name»',
          );
        }
        for (final MapEntry(key: id, value: at) in spread.entries) {
          final drawn = _sceneOf(cubit, id);
          expect(drawn.dx, closeTo(_scenePixel(at.x), 1e-6), reason: '$id x');
          expect(drawn.dy, closeTo(_scenePixel(at.y), 1e-6), reason: '$id y');
        }
      },
    );

    testWidgets(
      'fit-all never zooms below the fit-all floor and shows every node '
      'when they fit at it',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadFromWire(spread);
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
        );
        await tester.pumpAndSettle();
        cubit.graphController.zoomBy(0.35);
        await tester.pump();

        await _tapFitAll(tester);

        expect(tester.takeException(), isNull);
        _expectFitAllFrames(tester, cubit, kPhoneSurface);
      },
    );

    testWidgets(
      'fit-all shows every node of a layout that fits at the floor',
      (tester) async {
        // Close enough to Bob that the whole Field fits on the phone at the
        // fit-all floor.
        const compact = {
          'anna': (x: 1.0, y: 0.0),
          'boris': (x: 0.6, y: 0.8),
          'dima': (x: -0.6, y: -0.8),
        };
        await usePhoneSurface(tester);
        final cubit = await _loadFromWire(compact);
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
        );
        await tester.pumpAndSettle();
        cubit.graphController.zoomBy(0.35);
        await tester.pump();

        await _tapFitAll(tester);

        expect(tester.takeException(), isNull);
        _expectFitAllFrames(tester, cubit, kPhoneSurface);
        for (final id in _everyone) {
          expect(
            _onScreen(_screenOf(tester, _sceneOf(cubit, id)), kPhoneSurface),
            isTrue,
            reason: '$id on screen',
          );
        }
      },
    );
  });

  group('A layout placed inside the old ±10 range on the default viewport', () {
    const desktop = Size(1280, 800);
    const old = {
      'anna': (x: 0.0, y: 0.0),
      'boris': (x: 10.0, y: 10.0),
      'dima': (x: -10.0, y: -10.0),
    };

    /// This exact layout on this viewport, measured before the range was
    /// widened (stored fixture, not derived from today's constants).
    const before = (
      canvasCentre: 8192.0,
      pixelsPerUnit: 170.0,
      // The unpinned direct contact Kira's distance from Bob.
      firstRingRadius: 170.0,
      // After fit-all: the camera scale and every node body's on-screen width.
      fitAllScale: 0.45,
      fitAllBodyWidth: 20.0,
    );

    testWidgets(
      'keeps its positions and ring radius, or stays fully visible and no '
      'smaller on screen than before',
      (tester) async {
        final cubit = await _loadFromWire(old);
        addTearDown(cubit.close);
        final holder = ConstellationPresentationFrameHolder();
        await pumpConstellationBody(
          tester,
          cubit,
          size: desktop,
          presentationFrameHolder: holder,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final ego = _sceneOf(cubit, 'bob');
        final moved = <String>[
          for (final MapEntry(key: id, value: at) in old.entries)
            if ((_sceneOf(cubit, id) -
                        Offset(
                          before.canvasCentre + at.x * before.pixelsPerUnit,
                          before.canvasCentre + at.y * before.pixelsPerUnit,
                        ))
                    .distance >
                1e-6)
              id,
        ];
        final ringRadius = (_sceneOf(cubit, 'kira') - ego).distance;
        final ringChanged = (ringRadius - before.firstRingRadius).abs() >= 1;

        if (moved.isEmpty && !ringChanged) {
          // Outcome 1: the same positions and ring radius as before.
          return;
        }

        // Outcome 2: positions ($moved) or the ring radius changed, so the
        // layout must be fully visible after fit-all and no smaller on screen
        // than the same layout was before.
        await _tapFitAll(tester);
        final reason =
            'outcome 2 (moved: $moved, first ring ${ringRadius}px instead of '
            '${before.firstRingRadius}px)';
        expect(
          cubit.graphController.cameraScale,
          greaterThanOrEqualTo(before.fitAllScale - 1e-9),
          reason: '$reason: fit-all zoom no smaller than before',
        );
        for (final id in _everyone) {
          expect(
            _onScreen(_screenOf(tester, _sceneOf(cubit, id)), desktop),
            isTrue,
            reason: '$reason: $id visible after fit-all',
          );
          final body = holder.frame?.bodies['fp:$id'];
          expect(body, isNotNull, reason: '$reason: $id body drawn');
          expect(
            body!.width,
            greaterThanOrEqualTo(before.fitAllBodyWidth - 0.5),
            reason: '$reason: $id body no smaller on screen than before',
          );
        }
      },
    );
  });
}
