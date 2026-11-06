import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
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

    test("partitions the author's Posts by the pinned Posts", () {
      final at = DateTime.utc(2026, 10, 22);
      final result = constellationAuthorSatellites(
        authorId: 'p1',
        fieldRequests: const [],
        overlayPinnedRequests: const [],
        // A Post id among the anchored beacons alone is not enough.
        pinnedBeaconIds: const {'P2'},
        fieldPosts: [
          ConstellationPost(
            id: 'P1',
            authorId: 'p1',
            rootExcerpt: 'a',
            lastActivityAt: at,
          ),
          ConstellationPost(
            id: 'P2',
            authorId: 'p1',
            rootExcerpt: 'b',
            lastActivityAt: at,
          ),
          ConstellationPost(
            id: 'P3',
            authorId: 'p2',
            rootExcerpt: 'c',
            lastActivityAt: at,
          ),
        ],
        pinnedPostIds: const {'P1', 'P3'},
      );
      expect(result.pinnedIds, {'P1'});
      expect(result.unpinnedIds, {'P2'});
    });
  });

  group('constellationClampToDragBounds', () {
    const min = kConstellationCanvasCentre - 10 * 170.0;
    const max = kConstellationCanvasCentre + 10 * 170.0;

    test('keeps a point already inside', () {
      const inside = (
        x: kConstellationCanvasCentre + 52.0,
        y: kConstellationCanvasCentre - 148.0,
      );
      expect(constellationClampToDragBounds(inside), inside);
    });

    test('puts a point outside the envelope just inside its edge, moving '
        'only the axes that are out', () {
      final left = constellationClampToDragBounds((
        x: 100,
        y: kConstellationCanvasCentre,
      ));
      expect(
        left.x,
        closeTo(min + kConstellationEnvelopeClampInsetPixels, 1e-9),
      );
      expect(left.y, kConstellationCanvasCentre);

      final corner = constellationClampToDragBounds((
        x: max + 1252,
        y: min - 648,
      ));
      expect(
        corner.x,
        closeTo(max - kConstellationEnvelopeClampInsetPixels, 1e-9),
      );
      expect(
        corner.y,
        closeTo(min + kConstellationEnvelopeClampInsetPixels, 1e-9),
      );
      final units = constellationPointToV1Anchor(corner);
      expect(
        ConstellationAnchorPosition.validate(
          xUnits: units.xUnits,
          yUnits: units.yUnits,
          coordinateSpaceVersion: units.coordinateSpaceVersion,
        ),
        isA<ConstellationAnchorPositionValid>(),
      );
    });
  });

  group('constellationLimitClusterDelta', () {
    test('does not limit the parent by a companion near the envelope', () {
      const parentStart = (
        x: kConstellationCanvasCentre,
        y: kConstellationCanvasCentre,
      );
      // Companion near +10 units edge.
      const companionStart = (
        x: kConstellationCanvasCentre + 1652.0,
        y: kConstellationCanvasCentre,
      );
      final limited = constellationLimitClusterDelta(
        parentStart: parentStart,
        proposedParent: (
          x: kConstellationCanvasCentre + 500,
          y: kConstellationCanvasCentre,
        ),
        companionStarts: [companionStart],
      );
      expect(limited.x, closeTo(500, 1e-6));
    });

    test('a companion follows the parent but stops inside the envelope', () {
      const companionStart = (
        x: kConstellationCanvasCentre + 1652.0,
        y: kConstellationCanvasCentre,
      );
      final next = constellationCompanionPosition(
        companionStart: companionStart,
        parentDelta: (x: 500.0, y: 100.0),
      );
      expect((next.x - kConstellationCanvasCentre) / 170, closeTo(10, 1e-3));
      expect(next.y, closeTo(kConstellationCanvasCentre + 100, 1e-6));
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

  group('constellationLimitGroupDelta (group drag)', () {
    const centre = kConstellationCanvasCentre;
    const unit = 170.0;

    test('a group well inside the envelope moves by the full delta', () {
      final limited = constellationLimitGroupDelta(
        parentStart: (x: centre, y: centre),
        proposedParent: (x: centre + 300, y: centre - 200),
        memberStarts: const [(x: centre + 400, y: centre + 100)],
      );
      expect(limited.x, closeTo(300, 1e-6));
      expect(limited.y, closeTo(-200, 1e-6));
    });

    test('the member nearest a wall stops the whole group there, axis by '
        'axis, so the group stays rigid', () {
      // A member 100 px inside the right envelope edge.
      const member = (x: centre + 10 * unit - 100, y: centre);
      final limited = constellationLimitGroupDelta(
        parentStart: (x: centre, y: centre),
        proposedParent: (x: centre + 500, y: centre + 150),
        memberStarts: const [member],
      );
      expect(limited.x, closeTo(100, 0.01));
      expect(limited.y, closeTo(150, 1e-6), reason: 'slides along the wall');
      final moved = constellationGroupMemberPosition(
        memberStart: member,
        groupDelta: limited,
      );
      expect(moved.x - member.x, closeTo(limited.x, 1e-9));
      expect(moved.y - member.y, closeTo(limited.y, 1e-9));
    });

    test('the parent alone limits as constellationLimitClusterDelta does', () {
      const parentStart = (x: centre + 10 * unit - 50, y: centre);
      const proposed = (x: centre + 10 * unit + 400, y: centre - 80);
      final group = constellationLimitGroupDelta(
        parentStart: parentStart,
        proposedParent: proposed,
        memberStarts: const [],
      );
      final single = constellationLimitClusterDelta(
        parentStart: parentStart,
        proposedParent: proposed,
        companionStarts: const [],
      );
      expect(group.x, closeTo(single.x, 1e-6));
      expect(group.y, closeTo(single.y, 1e-6));
    });

    test('a member already outside the bounds does not hold the group; it '
        'slides on its own', () {
      const outside = (x: centre + 10 * unit + 200, y: centre);
      final limited = constellationLimitGroupDelta(
        parentStart: (x: centre, y: centre),
        proposedParent: (x: centre - 300, y: centre + 60),
        memberStarts: const [outside],
      );
      expect(limited.x, closeTo(-300, 1e-6));
      expect(limited.y, closeTo(60, 1e-6));
      final moved = constellationGroupMemberPosition(
        memberStart: outside,
        groupDelta: limited,
      );
      // Back inside the envelope, where it is valid again.
      expect(moved.x, closeTo(outside.x - 300, 1e-6));
      expect(moved.y, closeTo(centre + 60, 1e-6));
    });

    test('member weights scale how far each member may move for the same '
        'parent delta', () {
      const m1 = (x: centre + 200.0, y: centre);
      const m2 = (x: centre + 400.0, y: centre);
      final limited = constellationLimitGroupDelta(
        parentStart: (x: centre, y: centre),
        proposedParent: (x: centre + 300, y: centre),
        memberStarts: [m1, m2],
        memberWeights: [1.0, 0.5],
      );
      expect(limited.x, closeTo(300, 1e-6));
      final p1 = constellationGroupMemberPosition(
        memberStart: m1,
        groupDelta: limited,
      );
      final p2 = constellationGroupMemberPosition(
        memberStart: m2,
        groupDelta: limited,
        weight: .5,
      );
      expect(p1.x - m1.x, closeTo(300, 1e-6));
      expect(p2.x - m2.x, closeTo(150, 1e-6));
    });
  });
}
