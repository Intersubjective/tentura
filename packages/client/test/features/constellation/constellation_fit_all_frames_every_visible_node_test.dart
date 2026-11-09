// «Показать всё поле» / «Show whole field» (fit-all) frames every node drawn
// on the Field, even when one person sits far from everyone else, as
// Rearrange everyone and Move area leave people, and that takes a zoom below
// the district-detail scale. The first switch from text view to map frames
// the same way. Centre on me is unchanged.
//
// Every Field here comes from a real server response mapped by the real
// ConstellationRepository into a real store and ConstellationCubit, drawn by
// the real ConstellationBody. Everyone is anchored (as after Rearrange
// everyone), so two Fields with the same people get the same positions and
// their cameras can be compared.
//
// The roster: Bob (viewer), six direct contacts in a tight group around him,
// a Post by Bob and a Post by Anna (Post satellites), and Zoe, who was moved
// far away from the group.
//
// Bodies are checked in camera maths (scene body rect through the live camera
// into viewport pixels) and not against the drawn frame, because at a
// district-level zoom the frame may not draw node bodies at all.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'bob', displayName: 'Боб');
const _viewerNode = 'fp:bob';

/// Bob's direct contacts and where Rearrange everyone left each (units).
const _group = {
  'anna': ('Анна', 1.0, 0.0),
  'boris': ('Борис', -1.0, 0.0),
  'dima': ('Дима', 0.0, 1.0),
  'kira': ('Кира', 0.0, -1.0),
  'lena': ('Лена', 1.0, 1.0),
  'misha': ('Миша', -1.0, -1.0),
};

/// Zoe: a direct contact moved far away from the group.
const _far = 'zoe';
const _farNode = 'fp:zoe';

/// Where Zoe was moved: 10 units (1 700 px) out on each axis. Framing her
/// with the group needs a zoom below the district-detail scale on a phone and
/// on a desktop, yet above the Field's minimum zoom (0.1), so fit-all can show
/// everyone. Gaps of 20 000 scene px are covered by the scene-controller tests
/// in constellation_scene_fit_whole_field_test.dart: the Field's 16 384 px
/// canvas cannot hold them and its minimum zoom could not frame them.
const _farCorner = (10.0, 10.0);

/// How far (scene px) Zoe at [_farCorner] sits from Bob, at least.
const _farCornerMinDistance = 2000.0;

const _phone = kPhoneSurface;
const _desktop = Size(1280, 800);

// --- The server response ----------------------------------------------------

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
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
};

Map<String, dynamic> _edge(String src, String dst) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': 1,
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

Map<String, dynamic> _post(String id, String authorId, String excerpt) {
  final now = DateTime.now().toUtc();
  return {
    '__typename': 'v2_ConstellationPost',
    'id': id,
    'authorId': authorId,
    'lastActivityAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
    'expiresAt': now.add(const Duration(hours: 48)).toIso8601String(),
    'status': 0,
    'rootExcerpt': excerpt,
    'isPinned': false,
    'hiddenReachCount': 0,
    'has_unread': false,
  };
}

/// Bob's Field. [farAt] places Zoe (null: Zoe is not on the Field);
/// [extra] adds more anchored direct contacts: id → (x, y) units.
Map<String, dynamic> _fieldResponse({
  (double, double)? farAt = _farCorner,
  Map<String, (double, double)> extra = const {},
  String loadedAt = '2026-11-08T12:00:00.000Z',
}) {
  final people = <String, (String, double, double)>{
    ..._group,
    if (farAt != null) _far: ('Зоя', farAt.$1, farAt.$2),
    for (final MapEntry(:key, :value) in extra.entries)
      key: ('Гость $key', value.$1, value.$2),
  };
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': loadedAt,
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': [...people.keys],
      'peers': [
        _peer(_viewer.id, _viewer.displayName),
        for (final MapEntry(:key, :value) in people.entries)
          _peer(key, value.$1),
      ],
      'edges': [for (final id in people.keys) _edge(_viewer.id, id)],
      'requests': <dynamic>[],
      'posts': [
        _post('post-bob', _viewer.id, 'Кто едет в субботу на дачу?'),
        _post('post-anna', 'anna', 'Ищу лестницу на выходные'),
      ],
      'memberWebs': <dynamic>[],
      'anchorProjection': {
        '__typename': 'v2_ConstellationAnchorProjection',
        'revision': '1',
        'anchors': [
          _anchor(_viewer.id, 0, 0),
          for (final MapEntry(:key, :value) in people.entries)
            _anchor(key, value.$2, value.$3),
        ],
        'pinnedPeers': [
          for (final MapEntry(:key, :value) in people.entries)
            _peer(key, value.$1),
        ],
        'pinnedRequests': <dynamic>[],
        'supportPeers': <dynamic>[],
        'supportEdges': <dynamic>[],
        'serverFilteredBeaconIds': <dynamic>[],
        'serverFilteredBeaconCount': 0,
      },
    },
  };
}

/// Maps [response] through the real repository.
Future<ConstellationField> _mapFromWire(Map<String, dynamic> response) async {
  late final ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': response},
    [],
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
    },
  );
  return field;
}

/// The server as the store sees it: answers every fetch with [field].
final class _ServerField implements ConstellationRepositoryPort {
  _ServerField(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

typedef _Visit = ({
  ConstellationCubit cubit,
  ConstellationStoreFixture store,
  _ServerField server,
});

/// A Field cubit on a real store over the mapped [response], loaded.
Future<_Visit> _load(
  WidgetTester tester,
  Map<String, dynamic> response,
) async {
  final server = _ServerField(await _mapFromWire(response));
  final store = ConstellationStoreFixture(server, accountId: _viewer.id);
  final cubit = store.createCubit(viewer: _viewer);
  unawaited(cubit.load());
  await tester.runAsync(
    () => cubit.stream
        .firstWhere((s) => s.status is StateIsSuccess)
        .timeout(const Duration(seconds: 10)),
  );
  _openCubits.add(cubit);
  return (cubit: cubit, store: store, server: server);
}

/// Cubits a test loaded; closed at the end of the test body, before the
/// binding checks for pending timers (a Post arms an expiry timer).
final _openCubits = <ConstellationCubit>[];

/// A widget test on the Field that leaves no Field running behind it.
void _fieldTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(description, (tester) async {
  try {
    await body(tester);
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

Future<void> _mount(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required Size surface,
  required Locale locale,
}) async {
  await pumpConstellationBody(
    tester,
    cubit,
    size: surface,
    locale: locale,
  );
  await _pumpFrames(tester, 60);
}

/// The Field keeps animating chrome, so frames are pumped, not settled.
Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// --- What the user sees -----------------------------------------------------

/// The insets the Field frames its camera into (its own map chrome).
EdgeInsets _insets(ConstellationCubit cubit) {
  final insets = cubit.fieldCameraViewportSnapshotForTest;
  expect(insets, isNot(EdgeInsets.zero), reason: 'the Field reported insets');
  return insets;
}

/// The viewport minus the Field's camera insets, in viewport pixels.
Rect _safeRect(ConstellationCubit cubit) {
  final size = cubit.graphController.viewportSize;
  expect(size, isNotNull, reason: 'the Field viewport is known');
  return _insets(cubit).deflateRect(Offset.zero & size!);
}

/// Graph ids of every node drawn on the Field: people, Requests, Posts.
Set<String> _visibleNodes(ConstellationCubit cubit) => {
  for (final MapEntry(:key, :value)
      in cubit.graphController.renderSnapshot.topology.nodesById.entries)
    if (value.payload is FieldPersonNode || value.payload is FieldBeaconNode)
      key,
};

/// Graph ids of the Post satellites on the Field.
Set<String> _postNodes(ConstellationCubit cubit) => {
  for (final MapEntry(:key, :value)
      in cubit.graphController.renderSnapshot.topology.nodesById.entries)
    if (value.payload case FieldBeaconNode(post: _?)) key,
};

/// Scene position of [id] (null while not placed).
Offset? _scenePosition(ConstellationCubit cubit, String id) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(id);
  return point == null ? null : Offset(point.x, point.y);
}

/// [id]'s node body in viewport pixels through the current camera.
Rect? _bodyOnScreen(ConstellationCubit cubit, String id) {
  final node = cubit.graphController.renderSnapshot.topology.nodesById[id];
  final centre = _scenePosition(cubit, id);
  if (node == null || centre == null) {
    return null;
  }
  final scene = Rect.fromCenter(
    center: centre,
    width: node.size.width,
    height: node.size.height,
  );
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

/// The roster is what these tests mean: Zoe is placed far from Bob, and at
/// least one Post satellite is on the Field.
void _expectOffendingRoster(
  ConstellationCubit cubit, {
  required double minDistance,
}) {
  final bob = _scenePosition(cubit, _viewerNode);
  final zoe = _scenePosition(cubit, _farNode);
  expect(bob, isNotNull, reason: 'Bob is placed');
  expect(zoe, isNotNull, reason: 'Zoe is placed');
  expect(
    (zoe! - bob!).distance,
    greaterThan(minDistance),
    reason: 'Zoe sits where the anchor put her, far from Bob',
  );
  expect(_postNodes(cubit), isNotEmpty, reason: 'Post satellites are drawn');
}

/// The camera is below the district-detail scale (the Field does not fit at
/// it), and the body of every visible node, the far-away Zoe's included, lies
/// inside the safe viewport.
void _expectEveryBodyInSafeRect(
  ConstellationCubit cubit, {
  required String when,
}) {
  final safe = _safeRect(cubit);
  final scale = cubit.graphController.cameraScale;
  expect(
    scale,
    lessThan(kConstellationDistrictDetailScale),
    reason: '$when: the camera is not left at the district-detail floor',
  );
  final visible = _visibleNodes(cubit);
  expect(visible, contains(_farNode), reason: '$when: Zoe is on the Field');
  expect(visible, contains(_viewerNode), reason: '$when: Bob is on the Field');
  for (final id in visible) {
    final body = _bodyOnScreen(cubit, id);
    expect(body, isNotNull, reason: '$when: $id is placed');
    expect(
      _inside(safe, body!),
      isTrue,
      reason:
          '$when: $id body $body lies inside the safe viewport $safe '
          '(camera scale $scale)',
    );
  }
}

/// Centre on me's camera: Bob's body centred in the safe viewport, scale 1.
void _expectViewerCentredAtFullScale(
  ConstellationCubit cubit, {
  required String when,
}) {
  expect(
    cubit.graphController.cameraScale,
    closeTo(1, 1e-3),
    reason: '$when: scale 1',
  );
  final bob = _bodyOnScreen(cubit, _viewerNode)!;
  final safe = _safeRect(cubit);
  expect(
    (bob.center - safe.center).distance,
    lessThanOrEqualTo(1),
    reason: '$when: Bob ${bob.center} at the safe centre ${safe.center}',
  );
}

/// The camera as scale plus the scene point at the centre of the safe rect.
({double scale, Offset centre}) _camera(ConstellationCubit cubit) => (
  scale: cubit.graphController.cameraScale,
  centre: cubit.graphController.viewportLocalToScene(_safeRect(cubit).center),
);

void _expectSameCamera(
  ({double scale, Offset centre}) actual,
  ({double scale, Offset centre}) expected, {
  required String when,
}) {
  expect(
    actual.scale,
    closeTo(expected.scale, 1e-3),
    reason: '$when: same fit-all scale',
  );
  expect(
    (actual.centre - expected.centre).distance,
    lessThanOrEqualTo(1),
    reason:
        '$when: same fit-all centre (${actual.centre} vs ${expected.centre})',
  );
}

/// The user taps «Показать всё поле» / «Show whole field».
Future<void> _tapFitAll(WidgetTester tester) async {
  final control = find.byKey(TestIds.key(TestIds.constellationFitAll));
  expect(
    control.hitTestable(),
    findsOneWidget,
    reason: 'the fit-all control is on screen and tappable',
  );
  await tester.tap(control);
  await _pumpFrames(tester, 30);
}

/// The user drags the map and pinches it closer.
Future<void> _panAndPinch(WidgetTester tester) async {
  final viewport = find.byType(InteractiveViewer);
  final centre = tester.getCenter(viewport);
  final drag = await tester.startGesture(centre);
  await drag.moveBy(const Offset(40, 0));
  await tester.pump();
  await drag.moveBy(const Offset(50, 60));
  await tester.pump();
  await drag.up();
  await tester.pump(const Duration(milliseconds: 50));

  final a = await tester.startGesture(centre - const Offset(30, 0));
  final b = await tester.startGesture(centre + const Offset(30, 0));
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await a.moveBy(const Offset(-15, 0));
    await b.moveBy(const Offset(15, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await _pumpFrames(tester, 20);
}

void main() {
  group('Fit-all frames every visible node of the Field', () {
    _fieldTest(
      'a person arranged far from everyone else is framed together with the '
      'viewer, the people around him and the Post satellites, below the '
      'district-detail scale',
      (tester) async {
        final visit = await _load(tester, _fieldResponse());
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        _expectOffendingRoster(
          visit.cubit,
          minDistance: _farCornerMinDistance,
        );

        // Bob and Zoe alone, side by side, do not fit the safe viewport at
        // the district-detail scale.
        final safe = _safeRect(visit.cubit);
        final span =
            _scenePosition(visit.cubit, _farNode)! -
            _scenePosition(visit.cubit, _viewerNode)!;
        expect(
          math.min(safe.width / span.dx.abs(), safe.height / span.dy.abs()),
          lessThan(kConstellationDistrictDetailScale),
          reason: 'framing everyone needs a zoom below the district scale',
        );

        visit.cubit.fitWholeField(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);

        expect(tester.takeException(), isNull);
        _expectEveryBodyInSafeRect(visit.cubit, when: 'after fit-all');
      },
    );

    _fieldTest(
      'a freshly loaded Field whose camera sits on empty space: one tap on '
      'fit-all brings every visible node back into the safe viewport',
      (tester) async {
        // A new store and cubit load the offending roster, as a page reload
        // does.
        final visit = await _load(tester, _fieldResponse());
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        final insets = _insets(visit.cubit);
        _expectOffendingRoster(
          visit.cubit,
          minDistance: _farCornerMinDistance,
        );

        // The camera QA found after the reload: nothing in the safe viewport.
        // What put it there on the dev account is not known, so the test
        // places it there. The browser reload itself (web lifecycle) is only
        // provable by the web integration_test.
        visit.cubit.graphController.jumpToPosition(const Offset(-30000, 30000));
        await tester.pump();
        expect(
          visit.cubit.fieldAnyNodeBodyInSafeRectForTest(insets: insets),
          isFalse,
          reason: 'the Field shows empty space',
        );

        await _tapFitAll(tester);

        expect(
          visit.cubit.fieldAnyNodeBodyInSafeRectForTest(insets: insets),
          isTrue,
          reason: 'one fit-all tap brings nodes back',
        );
        _expectEveryBodyInSafeRect(
          visit.cubit,
          when: 'after one fit-all tap',
        );
      },
    );
  });

  group('Fit-all ignores nodes that are not on the Field', () {
    _fieldTest(
      'a far-away person the server no longer sends (hidden from the Field) '
      'does not change the fit-all camera',
      (tester) async {
        // Without that person.
        final without = await _load(tester, _fieldResponse());
        await _mount(tester, without.cubit, surface: _phone, locale: _ru);
        without.cubit.fitWholeField(insets: _insets(without.cubit));
        await _pumpFrames(tester, 30);
        final expected = _camera(without.cubit);
        await tester.pumpWidget(const SizedBox.shrink());
        await without.cubit.close();

        // Yan was on the Field far away, then hidden: the next fetch no
        // longer carries him.
        final visit = await _load(
          tester,
          _fieldResponse(extra: {'yan': (-40, -40)}),
        );
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        final yanLast = visit
            .cubit
            .graphController
            .renderSnapshot
            .layout
            ?.positions['fp:yan'];
        expect(yanLast, isNotNull, reason: 'Yan is laid out before the hide');
        visit.server.field = await _mapFromWire(
          _fieldResponse(loadedAt: '2026-11-08T12:05:00.000Z'),
        );
        await visit.store.store.requestRefresh(
          ConstellationRefreshReason.catchUp,
        );
        await _pumpFrames(tester, 90);
        expect(
          visit.cubit.state.field!.peers.map((p) => p.id),
          isNot(contains('yan')),
          reason: 'the hide reached the Field',
        );
        // Yan's last layout position lingers in the scene while he is hidden.
        // (This refresh drops it today; the test keeps it, so the far stale
        // position is in the layout when fit-all runs.)
        visit.cubit.graphController.scene.setLayoutPositions({
          ...visit.cubit.graphController.renderSnapshot.layout!.positions,
          'fp:yan': yanLast!,
        });
        await tester.pump();
        final lingering = visit
            .cubit
            .graphController
            .renderSnapshot
            .layout!
            .positions['fp:yan'];
        expect(lingering, isNotNull, reason: 'Yan’s last position lingers');
        expect(
          (Offset(lingering!.x, lingering.y) -
                  _scenePosition(visit.cubit, _viewerNode)!)
              .distance,
          greaterThan(_farCornerMinDistance),
          reason: 'and it is far from Bob',
        );
        expect(
          _visibleNodes(visit.cubit),
          isNot(contains('fp:yan')),
          reason: 'Yan is not drawn on the Field',
        );

        visit.cubit.fitWholeField(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);

        _expectSameCamera(
          _camera(visit.cubit),
          expected,
          when: 'after hiding a far-away person',
        );
        _expectEveryBodyInSafeRect(visit.cubit, when: 'after hiding');
      },
    );

    _fieldTest(
      'stale layout entries of nodes no longer on the Field (a removed '
      'person, forward-tree leftovers) do not change the fit-all camera',
      (tester) async {
        final visit = await _load(tester, _fieldResponse());
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        visit.cubit.fitWholeField(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);
        final expected = _camera(visit.cubit);

        final scene = visit.cubit.graphController.scene;
        final layout = visit.cubit.graphController.renderSnapshot.layout;
        expect(layout, isNotNull, reason: 'the Field is laid out');
        scene.setLayoutPositions({
          ...layout!.positions,
          'fp:removed-person': ScenePoint(x: -40000, y: -40000),
          'ft:overlay-leftover': ScenePoint(x: 60000, y: -60000),
        });
        await tester.pump();

        visit.cubit.fitWholeField(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);

        _expectSameCamera(
          _camera(visit.cubit),
          expected,
          when: 'with stale layout entries',
        );
      },
    );
  });

  group('Centre on me with a far-away person on the Field', () {
    _fieldTest(
      'puts the viewer at the centre of the safe viewport at scale 1, the '
      'same camera as on the Field without the far-away person and from any '
      'starting camera',
      (tester) async {
        // Baseline: Centre on me on the same Field without Zoe.
        final plain = await _load(tester, _fieldResponse(farAt: null));
        await _mount(tester, plain.cubit, surface: _phone, locale: _ru);
        plain.cubit.centerOnEgo(insets: _insets(plain.cubit));
        await _pumpFrames(tester, 30);
        final baseline = _camera(plain.cubit);
        await tester.pumpWidget(const SizedBox.shrink());
        await plain.cubit.close();

        final visit = await _load(tester, _fieldResponse());
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        _expectOffendingRoster(
          visit.cubit,
          minDistance: _farCornerMinDistance,
        );

        // From the fit-all camera.
        visit.cubit.fitWholeField(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);
        visit.cubit.centerOnEgo(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);
        _expectViewerCentredAtFullScale(visit.cubit, when: 'from fit-all');
        _expectSameCamera(
          _camera(visit.cubit),
          baseline,
          when: 'from fit-all, against the Field without Zoe',
        );

        // From a camera on empty space.
        visit.cubit.graphController.jumpToPosition(const Offset(-30000, 30000));
        await tester.pump();
        visit.cubit.centerOnEgo(insets: _insets(visit.cubit));
        await _pumpFrames(tester, 30);
        _expectViewerCentredAtFullScale(visit.cubit, when: 'from empty space');
        _expectSameCamera(
          _camera(visit.cubit),
          baseline,
          when: 'from empty space, against the Field without Zoe',
        );
      },
    );
  });

  group('A Field visit that starts in text view, with a far-away person', () {
    _fieldTest(
      'the first switch to map frames every visible node',
      (tester) async {
        final visit = await _load(tester, _fieldResponse());
        visit.cubit.setViewMode(ConstellationViewMode.text);
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        expect(visit.cubit.state.viewMode, ConstellationViewMode.text);

        visit.cubit.setViewMode(ConstellationViewMode.map);
        await _pumpFrames(tester, 60);

        _expectOffendingRoster(
          visit.cubit,
          minDistance: _farCornerMinDistance,
        );
        _expectEveryBodyInSafeRect(visit.cubit, when: 'first switch to map');
      },
    );

    _fieldTest(
      'after the user moves the map, text and back to map keep the user’s '
      'camera',
      (tester) async {
        final visit = await _load(tester, _fieldResponse());
        visit.cubit.setViewMode(ConstellationViewMode.text);
        await _mount(tester, visit.cubit, surface: _phone, locale: _ru);
        visit.cubit.setViewMode(ConstellationViewMode.map);
        await _pumpFrames(tester, 60);

        await _panAndPinch(tester);
        final user = _camera(visit.cubit);
        expect(
          visit.cubit.graphController.userCameraInputRevision.value,
          isPositive,
          reason: 'the user moved the camera',
        );

        visit.cubit.setViewMode(ConstellationViewMode.text);
        await _pumpFrames(tester, 20);
        visit.cubit.setViewMode(ConstellationViewMode.map);
        await _pumpFrames(tester, 60);

        _expectSameCamera(
          _camera(visit.cubit),
          user,
          when: 'second switch to map',
        );
      },
    );
  });

  for (final (name, surface, locale) in [
    ('phone 375×667, RU', _phone, _ru),
    ('desktop 1280×800, EN', _desktop, const Locale('en')),
  ]) {
    group('With a far-away person on the Field ($name)', () {
      _fieldTest(
        'tapping the fit-all control leaves every visible node in the safe '
        'viewport',
        (tester) async {
          final visit = await _load(tester, _fieldResponse());
          await _mount(tester, visit.cubit, surface: surface, locale: locale);
          _expectOffendingRoster(
            visit.cubit,
            minDistance: _farCornerMinDistance,
          );

          await _tapFitAll(tester);

          expect(tester.takeException(), isNull);
          _expectEveryBodyInSafeRect(visit.cubit, when: 'after fit-all tap');
        },
      );

      _fieldTest(
        'a visit that starts in text view frames every visible node on its '
        'first switch to map',
        (tester) async {
          final visit = await _load(tester, _fieldResponse());
          visit.cubit.setViewMode(ConstellationViewMode.text);
          await _mount(tester, visit.cubit, surface: surface, locale: locale);

          visit.cubit.setViewMode(ConstellationViewMode.map);
          await _pumpFrames(tester, 60);

          expect(tester.takeException(), isNull);
          _expectEveryBodyInSafeRect(
            visit.cubit,
            when: 'first switch to map',
          );
        },
      );
    });
  }
}

const _ru = Locale('ru');
