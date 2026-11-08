// The Field placement range is wider than the old ±10 units: a node can be
// anchored, fetched, drawn and dropped past 10 units, up to the shared bound
// kConstellationCoordinateMaxUnits, and existing ±10 layouts keep their
// on-screen positions.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';

/// The widened bound shared with the server and the database CHECK.
const _bound = kConstellationCoordinateMaxUnits;

const _viewer = Profile(id: 'bob', displayName: 'Боб');
const _pinnedPeerId = 'anna';
const _pinnedNodeId = 'fp:$_pinnedPeerId';
final _pinnedTarget = ConstellationAnchorTarget.person(_pinnedPeerId);

/// The scene pixel of a v1 coordinate (canvas centre + units × ring unit).
double _scenePixel(double units) =>
    kConstellationCanvasCentre + units * kConstellationRingUnitPixels;

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

Map<String, dynamic> _wireAnchor({
  required String targetId,
  required double x,
  required double y,
  required String revision,
}) => {
  '__typename': 'v2_ConstellationAnchor',
  'targetKind': 'PERSON',
  'targetId': targetId,
  'xUnits': x,
  'yUnits': y,
  'coordinateSpaceVersion': 1,
  'revision': revision,
  'placedAt': '2026-11-06T12:00:00.000Z',
};

/// The Field the server sends: Bob with three contacts, Anna anchored at
/// ([x], [y]).
Map<String, dynamic> _fieldResponse({required double x, required double y}) {
  final peers = [
    _peer('bob', 'Боб'),
    _peer('anna', 'Анна'),
    _peer('boris', 'Борис'),
    _peer('dima', 'Дима'),
  ];
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': '2026-11-06T12:00:00.000Z',
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': ['anna', 'boris', 'dima'],
      'peers': peers,
      'edges': [
        for (final dst in ['anna', 'boris', 'dima'])
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
          _wireAnchor(targetId: _pinnedPeerId, x: x, y: y, revision: '1'),
        ],
        'pinnedPeers': [_peer('anna', 'Анна')],
        'pinnedRequests': <dynamic>[],
        'supportPeers': <dynamic>[],
        'supportEdges': <dynamic>[],
        'serverFilteredBeaconIds': <dynamic>[],
        'serverFilteredBeaconCount': 0,
      },
    },
  };
}

/// What the server answers to a placement batch: every upsert stored as sent.
Map<String, dynamic> _applyResponse(Map<String, dynamic> variables) {
  final ops = (variables['ops']! as List).cast<Map<String, dynamic>>();
  return {
    '__typename': 'mutation_root',
    'constellationAnchorsApply': {
      '__typename': 'v2_ConstellationAnchorsApplyResult',
      'beforeRevision': '1',
      'afterRevision': '${1 + ops.length}',
      'results': [
        for (final (i, op) in ops.indexed)
          {
            '__typename': 'v2_ConstellationAnchorOpResult',
            'clientOpId': op['clientOpId'],
            'status': 'OK',
            'reason': null,
            'resultingTargetRevision': '${2 + i}',
            'anchor': op['kind'] == 'DELETE'
                ? null
                : _wireAnchor(
                    targetId: op['targetId']! as String,
                    x: ((op['position']! as Map)['xUnits']! as num).toDouble(),
                    y: ((op['position']! as Map)['yUnits']! as num).toDouble(),
                    revision: '${2 + i}',
                  ),
            'replayed': false,
          },
      ],
    },
  };
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with a Field cubit wired to the real repositories over a fake
/// HTTP transport whose server has Anna anchored at ([x], [y]).
Future<void> _withWireField({
  required double x,
  required double y,
  required List<WireSent> sent,
  required Future<void> Function(ConstellationCubit cubit) body,
}) => withRemoteWire(
  const {},
  sent,
  responseFor: (request) async => switch (request.operationName) {
    'ConstellationAnchorsApply' => _applyResponse(request.variables),
    // The manual layout history the first drop saves.
    'ConstellationLayoutSnapshotSave' => {
      '__typename': 'mutation_root',
      'constellationLayoutSnapshotSave': {
        '__typename': 'v2_ConstellationLayoutSnapshot',
        'id': 'snapshot-1',
      },
    },
    _ => _fieldResponse(x: x, y: y),
  },
  (remote) async {
    final sync = buildTestRealtimeSync();
    final store = ConstellationStoreFixture(
      ConstellationRepository(remote),
      accountId: _viewer.id,
      realtime: sync.case_,
    ).store;
    final cubit = ConstellationCubit(
      case_: store,
      anchorCase: ConstellationAnchorCase(
        env: const Env.fromEnvironment(),
        logger: Logger('WidePlacementRangeTest'),
      ),
      placementCase: ConstellationPlacementCase(
        ConstellationAnchorRepository(remote),
        store,
        FakeClockPort(),
        FakeWakeUpPort(),
        realtime: sync.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('WidePlacementRangeTest'),
      ),
      viewer: _viewer,
      forwardCase: buildTestForwardCase(_FakeForwardRepository()),
      loadOnCreate: false,
    );
    try {
      await cubit.load();
      await body(cubit);
    } finally {
      await cubit.close();
      await sync.port.dispose();
    }
  },
);

/// Picks up the anchored peer and drops it at [dropCentre], as the scene's
/// drag gesture does, then waits for the placement write to settle.
Future<void> _dragPinnedPeerTo(
  ConstellationCubit cubit,
  Offset dropCentre,
) async {
  cubit
    ..beginDragExisting(target: _pinnedTarget)
    ..updateDragPresentation(nodeId: _pinnedNodeId, sceneCentre: dropCentre);
  await cubit.onExistingNodeDrop(
    target: _pinnedTarget,
    sceneCentre: dropCentre,
  );
  for (var i = 0; i < 20 && cubit.state.hasPendingPlacementWrite; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await pumpEventQueue();
}

/// The single upsert position the client sent for the anchored peer.
Map<String, dynamic> _sentPosition(List<WireSent> sent) {
  final applies = sent.where(
    (s) => s.operationName == 'ConstellationAnchorsApply',
  );
  expect(applies, isNotEmpty, reason: 'the drop must be written');
  final ops = (applies.last.variables['ops']! as List)
      .cast<Map<String, dynamic>>()
      .where((op) => op['targetId'] == _pinnedPeerId);
  return ops.single['position']! as Map<String, dynamic>;
}

void main() {
  group('Anchor axis range check on the client', () {
    test('the shared bound is symmetric and wider than the old ±10', () {
      expect(_bound, greaterThan(10));
      expect(kConstellationCoordinateMinUnits, -_bound);
    });

    for (final (value, expected) in [
      (0.0, true),
      (10.0, true),
      (11.0, true),
      (-11.0, true),
      (_bound, true),
      (-_bound, true),
      (_bound + 0.001, false),
      (-(_bound + 0.001), false),
      (double.nan, false),
      (double.infinity, false),
      (double.negativeInfinity, false),
    ]) {
      test('isFiniteV1Axis($value) is $expected', () {
        expect(ConstellationAnchorPosition.isFiniteV1Axis(value), expected);
      });
    }

    test('a scene point 11 units out lies inside the placement envelope', () {
      expect(
        constellationPointWithinEnvelope((
          x: _scenePixel(11),
          y: _scenePixel(-11),
        )),
        isTrue,
      );
    });
  });

  group('Drag bounds', () {
    test('a node dragged to 11 units rests there, not at 10', () {
      final point = (x: _scenePixel(11), y: _scenePixel(-11));

      final rest = constellationClampToDragBounds(point);

      final units = constellationPointToV1Anchor(rest);
      expect(units.xUnits, closeTo(11, 1e-9));
      expect(units.yUnits, closeTo(-11, 1e-9));
    });

    test('a node dragged past the shared bound is held at the bound', () {
      final point = (x: _scenePixel(_bound + 2), y: _scenePixel(-_bound - 2));

      final rest = constellationClampToDragBounds(point);

      final units = constellationPointToV1Anchor(rest);
      expect(units.xUnits, lessThanOrEqualTo(_bound));
      expect(units.xUnits, closeTo(_bound, 2 / kConstellationRingUnitPixels));
      expect(units.yUnits, greaterThanOrEqualTo(-_bound));
      expect(units.yUnits, closeTo(-_bound, 2 / kConstellationRingUnitPixels));
    });
  });

  group('A Field anchored past the old ±10 limit', () {
    test(
      'is fetched from the server with the anchor at (11, -11) and composes '
      'the node there',
      () async {
        final sent = <WireSent>[];
        await _withWireField(
          x: 11,
          y: -11,
          sent: sent,
          body: (cubit) async {
            expect(
              cubit.state.confirmedProjection,
              isNotNull,
              reason: 'the Field with an anchor at (11, -11) must load',
            );
            final anchor = cubit.state.confirmedProjection!.anchors.single;
            expect(anchor.target, _pinnedTarget);
            expect(anchor.position.xUnits, 11);
            expect(anchor.position.yUnits, -11);

            // What the scene places the node from (no scene is mounted
            // here; the phone test checks the drawn position on screen).
            final overlaid = cubit.state.composition!.anchorOverlay.anchors
                .singleWhere((a) => a.target == _pinnedTarget);
            final point = constellationV1AnchorToPoint(overlaid.position);
            expect(point.x, closeTo(_scenePixel(11), 1e-6));
            expect(point.y, closeTo(_scenePixel(-11), 1e-6));
          },
        );
      },
    );
  });

  group('Dropping a node past the old ±10 limit', () {
    test('a drop at 11 units is sent to the server and kept as 11', () async {
      final sent = <WireSent>[];
      await _withWireField(
        x: 1,
        y: 1,
        sent: sent,
        body: (cubit) async {
          await _dragPinnedPeerTo(
            cubit,
            Offset(_scenePixel(11), _scenePixel(-11)),
          );

          final position = _sentPosition(sent);
          expect((position['xUnits']! as num).toDouble(), closeTo(11, 1e-6));
          expect((position['yUnits']! as num).toDouble(), closeTo(-11, 1e-6));

          final anchor = cubit.state.confirmedProjection!.anchors.singleWhere(
            (a) => a.target == _pinnedTarget,
          );
          expect(anchor.position.xUnits, closeTo(11, 1e-6));
          expect(anchor.position.yUnits, closeTo(-11, 1e-6));
        },
      );
    });

    test('a drop past the shared bound is sent clamped to the bound', () async {
      final sent = <WireSent>[];
      await _withWireField(
        x: 1,
        y: 1,
        sent: sent,
        body: (cubit) async {
          await _dragPinnedPeerTo(
            cubit,
            Offset(_scenePixel(_bound + 3), _scenePixel(0)),
          );

          final x = (_sentPosition(sent)['xUnits']! as num).toDouble();
          expect(
            ConstellationAnchorPosition.isFiniteV1Axis(x),
            isTrue,
            reason: 'the server must accept the clamped position, got $x',
          );
          expect(
            x,
            closeTo(_bound, 2 / kConstellationRingUnitPixels),
            reason: 'held at the shared bound',
          );
          expect(x, greaterThan(10), reason: 'not the old ±10 envelope');
        },
      );
    });
  });
}
