import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

// Pure patches the store applies between FULL reads (#672).

ConstellationTrustEdgeEntity _e(String src, String dst, [int tier = 1]) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

ConstellationAnchorProjection _projection({
  List<ConstellationPerson> pinnedPeers = const [],
  List<ConstellationTrustEdgeEntity> supportEdges = const [],
}) => ConstellationAnchorProjection(
  revision: ConstellationAnchorRevision.zero,
  anchors: const [],
  pinnedPeers: pinnedPeers,
  pinnedRequests: const [],
  supportPeers: const [],
  supportEdges: supportEdges,
  serverFilteredBeaconIds: const [],
  serverFilteredBeaconCount: 0,
);

ConstellationField _field({
  List<ConstellationPerson> peers = const [],
  List<ConstellationTrustEdgeEntity> edges = const [],
  ConstellationAnchorProjection? projection,
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 23),
  context: '',
  peers: peers,
  edges: edges,
  anchorProjection: projection,
);

void main() {
  test('a tier-1 trust replaces a derived tier-2 edge', () {
    final field = _field(
      peers: const [ConstellationPerson(id: 'p')],
      edges: [_e('me', 'p', 2)],
    );
    final patched = patchViewerRelations(
      field,
      viewerId: 'me',
      relations: const [
        ConstellationViewerRelation(personId: 'p', viewerTrusts: true),
      ],
    );
    expect(patched.edges, [_e('me', 'p')]);
    expect(patched.directContactIds, ['p']);
  });

  test('withdrawing trust leaves a derived tier-2 edge alone', () {
    final field = _field(
      peers: const [ConstellationPerson(id: 'p')],
      edges: [_e('me', 'p'), _e('p', 'me', 2)],
    );
    final patched = patchViewerRelations(
      field,
      viewerId: 'me',
      relations: const [
        ConstellationViewerRelation(personId: 'p', trustsViewer: false),
      ],
    );
    expect(patched.edges, [_e('me', 'p'), _e('p', 'me', 2)]);
    expect(identical(patched, field), isTrue);
  });

  test('a support edge is patched too, so the ring cannot keep it', () {
    final field = _field(
      peers: const [ConstellationPerson(id: 'p')],
      projection: _projection(supportEdges: [_e('me', 'p'), _e('p', 'me')]),
    );
    final patched = patchViewerRelations(
      field,
      viewerId: 'me',
      relations: const [
        ConstellationViewerRelation(personId: 'p', trustsViewer: false),
      ],
    );
    expect(
      constellationTrustBadges(field: patched, viewerId: 'me')['p'],
      ConstellationTrustBadge.youTrust,
    );
  });

  test('a pinned person outside the visible set becomes a contact node when '
      'trusted, and gets no edge of their own', () {
    final field = _field(
      projection: _projection(
        pinnedPeers: const [ConstellationPerson(id: 'p', visible: false)],
      ),
    );
    final patched = patchViewerRelations(
      field,
      viewerId: 'me',
      relations: const [
        ConstellationViewerRelation(
          personId: 'p',
          viewerTrusts: true,
          trustsViewer: true,
        ),
      ],
    );
    expect(patched.peers.single.contactOnly, isTrue);
    expect(patched.edges, [_e('me', 'p')]);
    expect(
      constellationTrustBadges(field: patched, viewerId: 'me')['p'],
      ConstellationTrustBadge.contactOnly,
    );
  });

  test('people not on the field are not added', () {
    final field = _field();
    final patched = patchViewerRelations(
      field,
      viewerId: 'me',
      relations: const [
        ConstellationViewerRelation(personId: 'x', viewerTrusts: true),
      ],
    );
    expect(identical(patched, field), isTrue);
  });
}
