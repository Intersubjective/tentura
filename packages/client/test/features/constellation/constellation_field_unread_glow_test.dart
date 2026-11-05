import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_field_unread_glow.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationField _field({
  List<ConstellationRequest> requests = const [],
  List<ConstellationPost> posts = const [],
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 11, 4),
  context: '',
  requests: requests,
  posts: posts,
  anchorProjection: ConstellationAnchorProjection(
    revision: _revision(1),
    anchors: const [],
    pinnedPeers: const [],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

void main() {
  test('rollup glow to author when beacon body is off the map', () {
    final field = _field(
      posts: [
        ConstellationPost(
          id: 'p1',
          authorId: 'author',
          rootExcerpt: 'hi',
          lastActivityAt: DateTime.utc(2026, 11, 4),
          hasUnread: true,
        ),
      ],
    );
    final glow = constellationFieldUnreadGlowGraphIds(
      field: field,
      beaconGraphIdsOnMap: const {},
      personGraphIdsOnMap: {constellationFieldPersonGraphId('author')},
    );
    expect(glow, {
      constellationFieldPersonGraphId('author'): 'author',
    });
  });

  test('glow under beacon when its body is on the map', () {
    final field = _field(
      requests: const [
        ConstellationRequest(
          id: 'r1',
          authorId: 'author',
          title: 'Need help',
          status: 0,
          hasUnread: true,
        ),
      ],
    );
    final beacon = constellationFieldBeaconGraphId('r1');
    final glow = constellationFieldUnreadGlowGraphIds(
      field: field,
      beaconGraphIdsOnMap: {beacon},
      personGraphIdsOnMap: {constellationFieldPersonGraphId('author')},
    );
    expect(glow, {beacon: 'author'});
  });

  test('skips read beacons', () {
    final field = _field(
      posts: [
        ConstellationPost(
          id: 'p1',
          authorId: 'author',
          rootExcerpt: 'hi',
          lastActivityAt: DateTime.utc(2026, 11, 4),
          hasUnread: false,
        ),
      ],
    );
    final glow = constellationFieldUnreadGlowGraphIds(
      field: field,
      beaconGraphIdsOnMap: {constellationFieldBeaconGraphId('p1')},
      personGraphIdsOnMap: const {},
    );
    expect(glow, isEmpty);
  });
}
