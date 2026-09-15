import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_density.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

const _ego = 'U_ego';
const _spacing = 16.0;
const _nodeSize = (width: 120.0, height: 120.0);

double _intersectionAreaForTest({
  required ConstellationPoint aCentre,
  required ConstellationSize aSize,
  required ConstellationPoint bCentre,
  required ConstellationSize bSize,
  double spacing = _spacing,
}) {
  final half = spacing / 2;
  final a = constellationRenderedBounds(centre: aCentre, size: aSize);
  final b = constellationRenderedBounds(centre: bCentre, size: bSize);
  final inflatedA = (
    left: a.left - half,
    top: a.top - half,
    right: a.right + half,
    bottom: a.bottom + half,
  );
  final inflatedB = (
    left: b.left - half,
    top: b.top - half,
    right: b.right + half,
    bottom: b.bottom + half,
  );
  final left = math.max(inflatedA.left, inflatedB.left);
  final top = math.max(inflatedA.top, inflatedB.top);
  final right = math.min(inflatedA.right, inflatedB.right);
  final bottom = math.min(inflatedA.bottom, inflatedB.bottom);
  if (right <= left || bottom <= top) {
    return 0;
  }
  return (right - left) * (bottom - top);
}

ConstellationField _fieldWithPins({
  required List<ConstellationPerson> automaticPeers,
  required List<ConstellationRequest> automaticRequests,
  required ConstellationAnchorProjection projection,
}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 11),
    context: 'ctx',
    peers: automaticPeers,
    requests: automaticRequests,
    anchorProjection: projection,
  );
}

ConstellationAnchor _personAnchor(String personId, double x, double y) =>
    ConstellationAnchor(
      target: ConstellationAnchorTarget.person(personId),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      ),
      revision: ConstellationAnchorRevision.zero,
      placedAt: DateTime.utc(2026, 9, 11),
    );

ConstellationAnchor _beaconAnchor(String beaconId, double x, double y) =>
    ConstellationAnchor(
      target: ConstellationAnchorTarget.beacon(beaconId),
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      ),
      revision: ConstellationAnchorRevision.zero,
      placedAt: DateTime.utc(2026, 9, 11, 0, 0, 1),
    );

void main() {
  group('composeConstellationPresentation', () {
    test('pinned people and support bypass peer cap budget', () {
      final automaticPeers = List.generate(
        kConstellationRenderPeerCap + 5,
        (i) => ConstellationPerson(id: 'auto-$i'),
      );
      final projection = ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [_personAnchor('pinned-a', 1, 1), _personAnchor('pinned-b', -1, 0)],
        pinnedPeers: [
          ConstellationPerson(id: 'pinned-a'),
          ConstellationPerson(id: 'pinned-b'),
        ],
        pinnedRequests: const [],
        supportPeers: [ConstellationPerson(id: 'support-x')],
        supportEdges: [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'support-x', tier: 1),
          ConstellationTrustEdgeEntity(src: 'support-x', dst: 'pinned-a', tier: 1),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );

      final field = _fieldWithPins(
        automaticPeers: automaticPeers,
        automaticRequests: const [],
        projection: projection,
      );

      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: field,
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: field.loadedAt,
        labelBudget: (perPerson: 3, total: 150),
      );

      expect(composed.eligiblePersonIds, containsAll(['pinned-a', 'pinned-b', 'support-x']));
      expect(composed.keptPeerIds.length, lessThanOrEqualTo(kConstellationRenderPeerCap + 3));
      expect(composed.keptPeerIds, containsAll(['pinned-a', 'pinned-b', 'support-x']));
    });

    test('pinned requests bypass label density budget', () {
      final prolificAuthor = 'author-heavy';
      final automaticRequests = [
        for (var i = 0; i < 20; i++)
          ConstellationRequest(
            id: 'auto-req-$i',
            authorId: prolificAuthor,
            title: 'Auto $i',
            status: 0,
          ),
      ];
      final projection = ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [_beaconAnchor('pinned-req', 2, 2)],
        pinnedPeers: const [],
        pinnedRequests: [
          ConstellationRequest(
            id: 'pinned-req',
            authorId: prolificAuthor,
            title: 'Pinned',
            status: 0,
          ),
        ],
        supportPeers: [ConstellationPerson(id: prolificAuthor)],
        supportEdges: [
          ConstellationTrustEdgeEntity(src: _ego, dst: prolificAuthor, tier: 1),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );

      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: [ConstellationPerson(id: prolificAuthor)],
          automaticRequests: automaticRequests,
          projection: projection,
        ),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: (perPerson: 1, total: 2),
      );

      expect(composed.labelPlan.drawnRequestIds, contains('pinned-req'));
      expect(composed.eligibleRequestIds, contains('pinned-req'));
    });

    test('after unpin, request re-enters ordinary label budget', () {
      const authorId = 'author-budget';
      const reqPinned = 'req-a';
      const reqSibling = 'req-b';
      final requests = [
        const ConstellationRequest(
          id: reqPinned,
          authorId: authorId,
          title: 'A',
          status: 0,
        ),
        const ConstellationRequest(
          id: reqSibling,
          authorId: authorId,
          title: 'B',
          status: 0,
        ),
      ];
      const filters = (
        capabilitySlugs: <String>{},
        location: LocationFilter.any,
        timing: TimingFilterAny(),
        includeUnspecified: true,
      );
      const budget = (perPerson: 1, total: 1);

      final pinned = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: const [ConstellationPerson(id: authorId)],
          automaticRequests: requests,
          projection: ConstellationAnchorProjection(
            revision: ConstellationAnchorRevision.zero,
            anchors: [_beaconAnchor(reqPinned, 1, 1)],
            pinnedPeers: const [],
            pinnedRequests: [requests.first],
            supportPeers: const [ConstellationPerson(id: authorId)],
            supportEdges: const [
              ConstellationTrustEdgeEntity(src: _ego, dst: authorId, tier: 1),
            ],
            serverFilteredBeaconIds: const [],
            serverFilteredBeaconCount: 0,
          ),
        ),
        localFilters: filters,
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: budget,
      );
      expect(pinned.labelPlan.drawnRequestIds, contains(reqPinned));

      final unpinned = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: const [ConstellationPerson(id: authorId)],
          automaticRequests: requests,
          projection: ConstellationAnchorProjection.empty,
        ),
        localFilters: filters,
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: budget,
      );
      expect(unpinned.labelPlan.drawnRequestIds.length, 1);
      expect(unpinned.labelPlan.overflowHiddenCountByAuthor[authorId], 1);
      expect(
        unpinned.labelPlan.drawnRequestIds.contains(reqPinned) &&
            unpinned.labelPlan.drawnRequestIds.contains(reqSibling),
        isFalse,
      );
    });

    test('request of author dropped by peer cap is not drawn', () {
      final fillerPeers = [
        for (var i = 0; i < kConstellationRenderPeerCap; i++)
          ConstellationPerson(id: 'auto-${i.toString().padLeft(3, '0')}'),
      ];
      const droppedAuthor = ConstellationPerson(id: 'zzz-author');
      final automaticPeers = [...fillerPeers, droppedAuthor];
      final edges = [
        for (final peer in automaticPeers)
          ConstellationTrustEdgeEntity(src: _ego, dst: peer.id, tier: 1),
      ];
      // Every peer is a request author so each charges the attributed holder
      // budget; zzz-author sorts last and is dropped when cap is full.
      final requests = [
        for (final peer in fillerPeers)
          ConstellationRequest(
            id: 'req-${peer.id}',
            authorId: peer.id,
            title: 'Filler',
            status: 0,
          ),
        const ConstellationRequest(
          id: 'req-dropped-author',
          authorId: 'zzz-author',
          title: 'Orphaned by cap',
          status: 0,
        ),
      ];
      final field = ConstellationField(
        loadedAt: DateTime.utc(2026, 9, 11),
        context: 'ctx',
        peers: automaticPeers,
        requests: requests,
        edges: edges,
        anchorProjection: ConstellationAnchorProjection.empty,
      );
      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: field,
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: field.loadedAt,
        labelBudget: (perPerson: 3, total: 500),
      );

      expect(composed.keptPeerIds, isNot(contains('zzz-author')));
      expect(
        composed.labelPlan.drawnRequestIds,
        isNot(contains('req-dropped-author')),
      );
      expect(composed.labelPlan.overflowHiddenCountByAuthor['zzz-author'], 1);
    });

    test('Map/Text eligible request IDs stay aligned', () {
      final projection = ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [_beaconAnchor('B1', 0, 0)],
        pinnedPeers: const [],
        pinnedRequests: [
          ConstellationRequest(id: 'B1', authorId: 'author', title: 'Pinned', status: 0),
        ],
        supportPeers: [ConstellationPerson(id: 'author')],
        supportEdges: [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'author', tier: 1),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );
      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: [ConstellationPerson(id: 'author')],
          automaticRequests: [
            ConstellationRequest(id: 'B2', authorId: 'author', title: 'Auto', status: 0),
          ],
          projection: projection,
        ),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: (perPerson: 3, total: 150),
      );

      expect(composed.eligibleRequestIds, composed.labelPlan.drawnRequestIds);
    });

    test('locally filtered pinned beacon releases support not needed elsewhere', () {
      final projection = ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [
          _beaconAnchor('B-hidden', 1, 1),
          _beaconAnchor('B-visible', 2, 2),
        ],
        pinnedPeers: const [],
        pinnedRequests: [
          ConstellationRequest(
            id: 'B-hidden',
            authorId: 'author-hidden',
            title: 'Hidden',
            status: 0,
            needs: ['alpha'],
          ),
          ConstellationRequest(
            id: 'B-visible',
            authorId: 'author-visible',
            title: 'Visible',
            status: 0,
          ),
        ],
        supportPeers: [
          ConstellationPerson(id: 'author-hidden'),
          ConstellationPerson(id: 'author-visible'),
          ConstellationPerson(id: 'bridge'),
        ],
        supportEdges: [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'bridge', tier: 1),
          ConstellationTrustEdgeEntity(src: 'bridge', dst: 'author-hidden', tier: 1),
          ConstellationTrustEdgeEntity(src: _ego, dst: 'author-visible', tier: 1),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );

      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: const [],
          automaticRequests: const [],
          projection: projection,
        ),
        localFilters: (
          capabilitySlugs: {'beta'},
          location: LocationFilter.any,
          timing: const TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: (perPerson: 3, total: 150),
      );

      expect(composed.locallyFilteredPinnedBeaconIds, {'B-hidden'});
      expect(
        composed.anchorOverlay.supportPeers.map((p) => p.id),
        isNot(contains('author-hidden')),
      );
      expect(
        composed.anchorOverlay.supportPeers.map((p) => p.id),
        isNot(contains('bridge')),
      );
      expect(
        composed.anchorOverlay.supportPeers.map((p) => p.id),
        contains('author-visible'),
      );
      expect(composed.eligibleRequestIds, contains('B-visible'));
    });

    test('connected pinned Request author stays in overlay support without automatic peers', () {
      final projection = ConstellationAnchorProjection(
        revision: ConstellationAnchorRevision.zero,
        anchors: [_beaconAnchor('B-pin', 1, 1)],
        pinnedPeers: const [],
        pinnedRequests: [
          ConstellationRequest(
            id: 'B-pin',
            authorId: 'author-capped',
            title: 'Pinned',
            status: 0,
          ),
        ],
        supportPeers: [ConstellationPerson(id: 'author-capped')],
        supportEdges: [
          ConstellationTrustEdgeEntity(src: _ego, dst: 'author-capped', tier: 1),
        ],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      );

      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: const [],
          automaticRequests: const [],
          projection: projection,
        ),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: (perPerson: 3, total: 150),
      );

      expect(composed.anchorOverlay.supportPeers.map((p) => p.id), ['author-capped']);
      expect(composed.keptPeerIds, contains('author-capped'));
      expect(composed.eligibleRequestIds, contains('B-pin'));
    });
  });

  group('computeConstellationPlacedLayout', () {
    ConstellationPathResolution _simplePaths() {
      return resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'peer-a', 'peer-b'},
        holderIds: {'peer-a'},
        edges: [(src: _ego, dst: 'peer-a', tier: 1)],
      );
    }

    test('person and beacon anchors stay independent hard positions', () {
      final paths = _simplePaths();
      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a'},
          pinnedPersonIds: {'peer-b'},
          pinnedRequestIds: {'B1'},
          supportPersonIds: const {},
          anchorByNodeId: {
            'peer-b': ConstellationAnchorPosition(
              xUnits: 4,
              yUnits: -3,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
            'B1': ConstellationAnchorPosition(
              xUnits: -2,
              yUnits: 5,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
          },
          priorHints: null,
          nodeSizes: const {},
          satelliteRequestIdsByAuthor: {'peer-a': ['B-auto']},
          requestAuthorById: {'B-auto': 'peer-a'},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      expect(
        layout.positions['peer-b'],
        constellationV1AnchorToPoint(
          ConstellationAnchorPosition(
            xUnits: 4,
            yUnits: -3,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
        ),
      );
      expect(
        layout.positions['B1'],
        constellationV1AnchorToPoint(
          ConstellationAnchorPosition(
            xUnits: -2,
            yUnits: 5,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
        ),
      );
    });

    test('unpinned beacon of a pinned author is not placed on ego', () {
      final paths = _simplePaths();
      const personAnchor = ConstellationAnchorPosition(
        xUnits: 4,
        yUnits: 0,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a'},
          pinnedPersonIds: {'peer-a'},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: {'peer-a': personAnchor},
          priorHints: null,
          nodeSizes: const {},
          satelliteRequestIdsByAuthor: const {
            'peer-a': ['B1'],
          },
          requestAuthorById: const {'B1': 'peer-a'},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      final ego = constellationCanvasCentrePoint();
      expect(layout.positions.containsKey('B1'), isTrue);
      final beacon = layout.positions['B1']!;
      final author = layout.positions['peer-a']!;
      expect(
        math.sqrt(
          math.pow(beacon.x - ego.x, 2) + math.pow(beacon.y - ego.y, 2),
        ),
        greaterThan(40),
      );
      expect(
        math.sqrt(
          math.pow(beacon.x - author.x, 2) + math.pow(beacon.y - author.y, 2),
        ),
        lessThan(150),
      );
    });

    test('unpinned beacon of an automatic author is not placed on ego', () {
      final paths = _simplePaths();
      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a'},
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: null,
          nodeSizes: const {},
          satelliteRequestIdsByAuthor: const {
            'peer-a': ['B1'],
          },
          requestAuthorById: const {'B1': 'peer-a'},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      final ego = constellationCanvasCentrePoint();
      expect(layout.positions.containsKey('B1'), isTrue);
      final beacon = layout.positions['B1']!;
      expect(
        math.sqrt(
          math.pow(beacon.x - ego.x, 2) + math.pow(beacon.y - ego.y, 2),
        ),
        greaterThan(40),
      );
    });

    test('exact overlapping anchors are preserved', () {
      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: _simplePaths(),
          automaticKeptPeerIds: const {},
          pinnedPersonIds: {'p1', 'p2'},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: {
            'p1': const ConstellationAnchorPosition(
              xUnits: 1,
              yUnits: 1,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
            'p2': const ConstellationAnchorPosition(
              xUnits: 1,
              yUnits: 1,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
          },
          priorHints: null,
          nodeSizes: const {},
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      expect(layout.positions['p1'], layout.positions['p2']);
    });

    test('topology change keeps pinned coordinates', () {
      final anchor = const ConstellationAnchorPosition(
        xUnits: 3,
        yUnits: -4,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final beforePaths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'peer-a'},
        holderIds: {'peer-a'},
        edges: [(src: _ego, dst: 'peer-a', tier: 1)],
      );
      final afterPaths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'peer-a', 'peer-b'},
        holderIds: {'peer-a', 'peer-b'},
        edges: [
          (src: _ego, dst: 'peer-a', tier: 1),
          (src: _ego, dst: 'peer-b', tier: 1),
        ],
      );

      ConstellationPlacedLayoutInput inputFor(
        ConstellationPathResolution paths,
      ) =>
          (
            egoId: _ego,
            paths: paths,
            automaticKeptPeerIds: paths.keep,
            pinnedPersonIds: {'peer-a'},
            pinnedRequestIds: const {},
            supportPersonIds: const {},
            anchorByNodeId: {'peer-a': anchor},
            priorHints: null,
            nodeSizes: const {},
            satelliteRequestIdsByAuthor: const {},
            requestAuthorById: const <String, String>{},
            egoOwnRequestIds: const {},
            spacing: _spacing,
            maxHops: 3,
            viewportClass: ConstellationViewportClass.expanded,
            footprints: const <String, ConstellationFootprint>{},
          );

      final before = computeConstellationPlacedLayout(input: inputFor(beforePaths));
      final after = computeConstellationPlacedLayout(input: inputFor(afterPaths));

      expect(after.positions['peer-a'], before.positions['peer-a']);
      expect(after.positions['peer-a'], constellationV1AnchorToPoint(anchor));
    });

    test('layout is repeatable for identical input', () {
      final input = (
        egoId: _ego,
        paths: _simplePaths(),
        automaticKeptPeerIds: {'peer-a'},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const {'peer-a': (width: 80.0, height: 80.0)},
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
      );
      final first = computeConstellationPlacedLayout(input: input);
      final second = computeConstellationPlacedLayout(input: input);
      expect(second.positions, first.positions);
    });

    test('all four envelope corners are accepted for anchors', () {
      for (final corner in [
        (x: -10.0, y: -10.0),
        (x: -10.0, y: 10.0),
        (x: 10.0, y: -10.0),
        (x: 10.0, y: 10.0),
      ]) {
        final point = constellationV1AnchorToPoint(
          ConstellationAnchorPosition(
            xUnits: corner.x,
            yUnits: corner.y,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
        );
        expect(constellationPointWithinEnvelope(point), isTrue);
      }
    });

    test('automatic person avoids pinned anchor without moving pin', () {
      const pinnedAnchor = ConstellationAnchorPosition(
        xUnits: 2,
        yUnits: 0,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final pinnedPoint = constellationV1AnchorToPoint(pinnedAnchor);
      final paths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'pinned-peer', 'auto-peer'},
        holderIds: {'pinned-peer', 'auto-peer'},
        edges: [
          (src: _ego, dst: 'pinned-peer', tier: 1),
          (src: _ego, dst: 'auto-peer', tier: 1),
        ],
      );

      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'pinned-peer', 'auto-peer'},
          pinnedPersonIds: {'pinned-peer'},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: {'pinned-peer': pinnedAnchor},
          priorHints: null,
          nodeSizes: const {
            'pinned-peer': _nodeSize,
            'auto-peer': _nodeSize,
          },
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      expect(layout.positions['pinned-peer'], pinnedPoint);
      expect(layout.positions.containsKey('auto-peer'), isTrue);
      expect(layout.positions['auto-peer'], isNot(equals(pinnedPoint)));
      expect(
        _intersectionAreaForTest(
          aCentre: layout.positions['pinned-peer']!,
          aSize: _nodeSize,
          bCentre: layout.positions['auto-peer']!,
          bSize: _nodeSize,
        ),
        0,
      );
    });

    test('exhausted collision candidates still place automatic node', () {
      final paths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'pinned-peer', 'crowded-auto'},
        holderIds: {'pinned-peer', 'crowded-auto'},
        edges: [
          (src: _ego, dst: 'pinned-peer', tier: 1),
          (src: _ego, dst: 'crowded-auto', tier: 1),
        ],
      );
      final baseline = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'crowded-auto'},
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: null,
          nodeSizes: const {'crowded-auto': _nodeSize},
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );
      final crowdedIdeal = baseline.positions['crowded-auto']!;
      final pinnedAnchor = constellationPointToV1Anchor(crowdedIdeal);
      final pinnedPoint = crowdedIdeal;

      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'pinned-peer', 'crowded-auto'},
          pinnedPersonIds: {'pinned-peer'},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: {'pinned-peer': pinnedAnchor},
          priorHints: null,
          nodeSizes: const {
            'pinned-peer': _nodeSize,
            'crowded-auto': _nodeSize,
          },
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      expect(layout.positions['pinned-peer'], pinnedPoint);
      expect(layout.positions.containsKey('crowded-auto'), isTrue);
      final overlap = _intersectionAreaForTest(
        aCentre: layout.positions['pinned-peer']!,
        aSize: _nodeSize,
        bCentre: layout.positions['crowded-auto']!,
        bSize: _nodeSize,
      );
      if (overlap == 0) {
        expect(layout.positions['crowded-auto'], isNot(equals(crowdedIdeal)));
      } else {
        expect(overlap, greaterThan(0));
      }
    });

    test('two automatic people do not stack when collision-free space exists', () {
      final paths = resolveConstellationPaths(
        egoId: _ego,
        visiblePeerIds: {'peer-a', 'peer-b'},
        holderIds: {'peer-a', 'peer-b'},
        edges: [
          (src: _ego, dst: 'peer-a', tier: 1),
          (src: _ego, dst: 'peer-b', tier: 1),
        ],
      );

      final layout = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a', 'peer-b'},
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: null,
          nodeSizes: const {
            'peer-a': _nodeSize,
            'peer-b': _nodeSize,
          },
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      final a = layout.positions['peer-a'];
      final b = layout.positions['peer-b'];
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(equals(b)));
      expect(
        _intersectionAreaForTest(
          aCentre: a!,
          aSize: _nodeSize,
          bCentre: b!,
          bSize: _nodeSize,
        ),
        0,
      );
    });

    test('prior hint applies only when viewport class matches', () {
      final paths = _simplePaths();
      final hintPoint = (x: 2200.0, y: 2100.0);
      final withHint = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a'},
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: (
            positions: {'peer-a': hintPoint},
            ring: { 'peer-a': 1},
            viewportClass: ConstellationViewportClass.compact,
          ),
          nodeSizes: const {'peer-a': (width: 64, height: 64)},
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.compact,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );
      final withoutHint = computeConstellationPlacedLayout(
        input: (
          egoId: _ego,
          paths: paths,
          automaticKeptPeerIds: {'peer-a'},
          pinnedPersonIds: const {},
          pinnedRequestIds: const {},
          supportPersonIds: const {},
          anchorByNodeId: const {},
          priorHints: (
            positions: {'peer-a': hintPoint},
            ring: {'peer-a': 1},
            viewportClass: ConstellationViewportClass.compact,
          ),
          nodeSizes: const {'peer-a': (width: 64, height: 64)},
          satelliteRequestIdsByAuthor: const {},
          requestAuthorById: const <String, String>{},
          egoOwnRequestIds: const {},
          spacing: _spacing,
          maxHops: 3,
          viewportClass: ConstellationViewportClass.expanded,
          footprints: const <String, ConstellationFootprint>{},
        ),
      );

      expect(withHint.positions['peer-a'], hintPoint);
      expect(withoutHint.positions['peer-a'], isNot(equals(hintPoint)));
    });
  });

  group('computeConstellationPinPosition', () {
    test('returns composed coordinate when already laid out', () {
      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: _fieldWithPins(
          automaticPeers: [ConstellationPerson(id: 'peer-a')],
          automaticRequests: const [],
          projection: ConstellationAnchorProjection(
            revision: ConstellationAnchorRevision.zero,
            anchors: [_personAnchor('peer-a', 2, -1)],
            pinnedPeers: [ConstellationPerson(id: 'peer-a')],
            pinnedRequests: const [],
            supportPeers: const [],
            supportEdges: const [],
            serverFilteredBeaconIds: const [],
            serverFilteredBeaconCount: 0,
          ),
        ),
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: DateTime.utc(2026, 9, 11),
        labelBudget: (perPerson: 3, total: 150),
      );

      final layoutInput = layoutInputFromComposition(
        viewerId: _ego,
        composition: composed,
        labelPlan: composed.labelPlan,
        nodeSizes: const {},
        spacing: _spacing,
      );

      final pin = computeConstellationPinPosition(
        target: ConstellationAnchorTarget.person('peer-a'),
        layoutInput: layoutInput,
      );

      expect(pin?.xUnits, 2);
      expect(pin?.yUnits, -1);
    });

    test('density-excluded beacon gets fallback without moving other nodes', () {
      final author = 'author-a';
      final hiddenBeacon = 'B-z-hidden';
      final field = _fieldWithPins(
        automaticPeers: [ConstellationPerson(id: author)],
        automaticRequests: [
          ConstellationRequest(
            id: 'B-a-visible',
            authorId: author,
            title: 'Visible on map',
            status: 0,
          ),
          ConstellationRequest(
            id: hiddenBeacon,
            authorId: author,
            title: 'Hidden by density',
            status: 0,
          ),
        ],
        projection: ConstellationAnchorProjection.empty,
      );

      final composed = composeConstellationPresentation(
        viewerId: _ego,
        field: field,
        localFilters: const (
          capabilitySlugs: {},
          location: LocationFilter.any,
          timing: TimingFilterAny(),
          includeUnspecified: true,
        ),
        asOfUtc: field.loadedAt,
        labelBudget: (perPerson: 1, total: 1),
      );

      expect(composed.labelPlan.drawnRequestIds, contains('B-a-visible'));
      expect(composed.labelPlan.drawnRequestIds, isNot(contains(hiddenBeacon)));

      final layoutInput = layoutInputFromComposition(
        viewerId: _ego,
        composition: composed,
        labelPlan: composed.labelPlan,
        nodeSizes: {
          author: (width: 72.0, height: 72.0),
          'B-a-visible': (width: 72.0, height: 72.0),
          hiddenBeacon: (width: 72.0, height: 72.0),
        },
        spacing: _spacing,
        viewportClass: ConstellationViewportClass.compact,
        footprints: const <String, ConstellationFootprint>{},
      );

      final beforeLayout = computeConstellationPlacedLayout(input: layoutInput);
      final fallback = computeConstellationPinPosition(
        target: ConstellationAnchorTarget.beacon(hiddenBeacon),
        layoutInput: layoutInput,
      );
      final afterLayout = computeConstellationPlacedLayout(input: layoutInput);

      expect(fallback, isNotNull);
      expect(afterLayout.positions, beforeLayout.positions);
      expect(composed.anchorOverlay.anchors, isEmpty);
    });

    test('compact and expanded viewport round-trip normalized coordinates', () {
      const anchor = ConstellationAnchorPosition(
        xUnits: 5,
        yUnits: -6,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final point = constellationV1AnchorToPoint(anchor);
      final roundTrip = constellationPointToV1Anchor(point);
      expect(roundTrip.xUnits, closeTo(anchor.xUnits, 1e-9));
      expect(roundTrip.yUnits, closeTo(anchor.yUnits, 1e-9));

      expect(
        constellationViewportClassForSize(width: 390),
        ConstellationViewportClass.compact,
      );
      expect(
        constellationViewportClassForSize(width: 1440),
        ConstellationViewportClass.expanded,
      );
    });
  });
}
