import 'dart:math';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

const kSyntheticFieldDefaultSeed = 235;

const _viewerId = 'ego';
const _directShare = 0.15;
const _anchoredShare = 0.1;

/// Deterministic synthetic constellation field for benchmarks (issue #235 U01).
///
/// [size] people (`p0`..) and [size] requests (`r0`..) around the viewer
/// (`ego`), with trust edges and a valid anchor projection. The same
/// [size] and [seed] always yield an equal field.
ConstellationField syntheticConstellationField({
  required int size,
  int seed = kSyntheticFieldDefaultSeed,
}) {
  final random = Random(seed);
  final loadedAt = DateTime.utc(2026, 10, 7, 12);

  final peers = [
    for (var i = 0; i < size; i++)
      ConstellationPerson(id: 'p$i', displayName: 'Person $i'),
  ];

  final directCount = max(1, (size * _directShare).round());
  final edges = <ConstellationTrustEdgeEntity>[
    for (var i = 0; i < directCount; i++)
      ConstellationTrustEdgeEntity(src: _viewerId, dst: 'p$i', tier: 1),
    for (var i = directCount; i < size; i++)
      ConstellationTrustEdgeEntity(
        src: 'p${random.nextInt(directCount)}',
        dst: 'p$i',
        tier: 2,
      ),
  ];

  final requests = [
    for (var i = 0; i < size; i++)
      ConstellationRequest(
        id: 'r$i',
        authorId: 'p${random.nextInt(size)}',
        title: 'Request $i',
        status: 0,
      ),
  ];

  final anchoredCount = max(1, (size * _anchoredShare).round());
  final anchoredPeers = peers.take(anchoredCount).toList();
  final anchoredRequests = requests.take(anchoredCount).toList();
  final revision = ConstellationAnchorRevision(BigInt.one);
  const extent = kConstellationCoordinateMaxUnits;
  ConstellationAnchorPosition position() => ConstellationAnchorPosition(
    xUnits: (random.nextDouble() * 2 - 1) * extent,
    yUnits: (random.nextDouble() * 2 - 1) * extent,
    coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
  );
  final anchors = [
    for (final peer in anchoredPeers)
      ConstellationAnchor(
        target: ConstellationAnchorTarget.person(peer.id),
        position: position(),
        revision: revision,
        placedAt: loadedAt,
      ),
    for (final request in anchoredRequests)
      ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon(request.id),
        position: position(),
        revision: revision,
        placedAt: loadedAt,
      ),
  ];

  return ConstellationField(
    loadedAt: loadedAt,
    context: '',
    peers: peers,
    edges: edges,
    requests: requests,
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: anchors,
      pinnedPeers: anchoredPeers,
      pinnedRequests: anchoredRequests,
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}
