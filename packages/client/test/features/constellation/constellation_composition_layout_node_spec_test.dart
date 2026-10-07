import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

const _ego = 'U_ego';
final _asOf = DateTime.utc(2026, 10, 3, 12);

ConstellationField _field({
  List<ConstellationRequest> requests = const [],
  List<ConstellationPost> posts = const [],
  ConstellationAnchorProjection? projection,
}) => ConstellationField(
  loadedAt: _asOf,
  context: 'ctx',
  peers: [ConstellationPerson(id: 'peer-a')],
  edges: [ConstellationTrustEdgeEntity(src: _ego, dst: 'peer-a', tier: 1)],
  requests: requests,
  posts: posts,
  memberWebs: const [],
  anchorProjection: projection,
);

ConstellationRequest _request() => ConstellationRequest(
  id: 'req-1',
  authorId: 'peer-a',
  title: 'Move a sofa',
  status: 0,
);

ConstellationPost _post() => ConstellationPost(
  id: 'post-1',
  authorId: 'peer-a',
  rootExcerpt: 'Who has a ladder?',
  lastActivityAt: _asOf.subtract(const Duration(hours: 1)),
  isPinned: true,
);

ConstellationAnchorProjection _projectionPinning(String beaconId) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon(beaconId),
          position: ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 1,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
          revision: ConstellationAnchorRevision.zero,
          placedAt: DateTime.utc(2026, 10, 1),
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    );

ConstellationComposedPresentation _compose(ConstellationField field) =>
    composeConstellationPresentation(
      viewerId: _ego,
      field: field,
      localFilters: const (
        capabilitySlugs: {},
        location: LocationFilter.any,
        timing: TimingFilterAny(),
        includeUnspecified: true,
      ),
      asOfUtc: _asOf,
      labelBudget: (perPerson: 3, total: 150),
      selectedRequestWebs: const [],
    );

void main() {
  group('composition emits domain layout node specs', () {
    test('every composed Beacon node is a LayoutNodeSpec', () {
      final composed = _compose(
        _field(requests: [_request()], posts: [_post()]),
      );

      expect(composed.beaconNodes, hasLength(2));
      expect(composed.beaconNodes, everyElement(isA<LayoutNodeSpec>()));
    });

    test('specs carry the Beacon id and label', () {
      final composed = _compose(
        _field(requests: [_request()], posts: [_post()]),
      );
      final byId = {for (final node in composed.beaconNodes) node.id: node};

      expect(byId.keys, unorderedEquals(['req-1', 'post-1']));
      expect(byId['req-1']!.label, 'Move a sofa');
      expect(byId['post-1']!.label, 'Who has a ladder?');
    });

    test('specs carry the pinned flag of the anchored Beacon only', () {
      final composed = _compose(
        _field(
          requests: [_request()],
          posts: [_post()],
          projection: _projectionPinning('post-1'),
        ),
      );
      final byId = {for (final node in composed.beaconNodes) node.id: node};

      expect(byId['post-1']!.pinned, isTrue);
      expect(byId['req-1']!.pinned, isFalse);
    });
  });
}
