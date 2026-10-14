import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

void main() {
  group('constellationAuthorSatellites', () {
    test('partitions pinned vs unpinned from field and overlay', () {
      const field = ConstellationRequest(
        id: 'B1',
        authorId: 'p1',
        title: 'A',
        status: 0,
      );
      const overlayOnly = ConstellationRequest(
        id: 'B2',
        authorId: 'p1',
        title: 'B',
        status: 0,
      );
      const otherAuthor = ConstellationRequest(
        id: 'B3',
        authorId: 'p2',
        title: 'C',
        status: 0,
      );
      final result = constellationAuthorSatellites(
        authorId: 'p1',
        fieldRequests: const [field, otherAuthor],
        overlayPinnedRequests: const [overlayOnly],
        pinnedBeaconIds: const {'B2'},
      );
      expect(result.pinnedIds, {'B2'});
      expect(result.unpinnedIds, {'B1'});
    });
  });

  group('constellationLimitClusterDelta', () {
    test('does not limit the parent by a companion near the envelope', () {
      const parentStart = (x: 2048.0, y: 2048.0);
      // Companion near +10 units edge (2048 + 10*170 = 3748).
      const companionStart = (x: 3700.0, y: 2048.0);
      final limited = constellationLimitClusterDelta(
        parentStart: parentStart,
        proposedParent: (x: 2048 + 500, y: 2048),
        companionStarts: const [companionStart],
      );
      expect(limited.x, closeTo(500, 1e-6));
    });

    test('a companion follows the parent but stops inside the envelope', () {
      const companionStart = (x: 3700.0, y: 2048.0);
      final next = constellationCompanionPosition(
        companionStart: companionStart,
        parentDelta: (x: 500.0, y: 100.0),
      );
      expect((next.x - 2048) / 170, closeTo(10, 1e-3));
      expect(next.y, closeTo(2148, 1e-6));
    });
  });

  group('constellationAnchorAdoptedAt', () {
    test('matches intended position within epsilon', () {
      final anchors = [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('p1'),
          position: const ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 2,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 9, 11),
        ),
      ];
      expect(
        constellationAnchorAdoptedAt(
          anchors: anchors,
          target: ConstellationAnchorTarget.person('p1'),
          intended: const ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 2,
            coordinateSpaceVersion: 1,
          ),
        ),
        isTrue,
      );
      expect(
        constellationAnchorAdoptedAt(
          anchors: anchors,
          target: ConstellationAnchorTarget.person('p1'),
          intended: const ConstellationAnchorPosition(
            xUnits: 3,
            yUnits: 2,
            coordinateSpaceVersion: 1,
          ),
        ),
        isFalse,
      );
    });
  });
}
