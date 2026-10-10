import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

const _ego = 'U_ego';
const _hidden = 'U_pinned_hidden';

final _pinPosition = ConstellationAnchorPosition(
  xUnits: 2,
  yUnits: 1,
  coordinateSpaceVersion: 1,
);

ConstellationAnchorProjection _projection({
  required bool pinned,
  bool withPeerRecord = true,
}) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: [
        if (pinned)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(_hidden),
            position: _pinPosition,
            revision: ConstellationAnchorRevision.zero,
            placedAt: DateTime.utc(2026, 9, 11),
          ),
      ],
      pinnedPeers: [
        if (pinned && withPeerRecord)
          const ConstellationPerson(id: _hidden, visible: false),
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    );

ConstellationComposedPresentation _compose({
  required bool pinned,
  bool withPeerRecord = true,
}) {
  final field = ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 11),
    context: 'ctx',
    peers: [
      for (var i = 0; i < 300; i++)
        ConstellationPerson(id: 'auto-$i', visible: true),
    ],
    // Automatic peers only compete for the cap as holders, i.e. as authors of
    // Requests; the pinned person authors none.
    requests: [
      for (var i = 0; i < 300; i++)
        ConstellationRequest(
          id: 'B_auto_$i',
          authorId: 'auto-$i',
          title: 'Request $i',
          status: 0,
        ),
    ],
    edges: [
      for (var i = 0; i < 300; i++)
        ConstellationTrustEdgeEntity(src: _ego, dst: 'auto-$i', tier: 1),
    ],
    anchorProjection: _projection(
      pinned: pinned,
      withPeerRecord: withPeerRecord,
    ),
  );
  return composeConstellationPresentation(
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
}

// Blocks (either direction), unblock and unreadable pinned Requests are
// decided by the server reader (see the pg test next to the field repository);
// the client only renders what the projection carries, so its side of those
// rules is that a pin absent from the projection is never drawn.
void main() {
  group('pinned person outside the visible set', () {
    test('is kept, eligible and unattached when 300 peers compete for the cap',
        () {
      final composed = _compose(pinned: true);

      // The cap really bites: automatic peers are dropped.
      final keptAutomatic =
          composed.keptPeerIds.where((id) => id.startsWith('auto-'));
      expect(composed.renderBudgetCapped, isTrue);
      expect(keptAutomatic.length, lessThan(300));

      expect(composed.keptPeerIds, contains(_hidden));
      expect(composed.eligiblePersonIds, contains(_hidden));

      // No path, no stub, no satellites.
      expect(composed.paths.parent.containsKey(_hidden), isFalse);
      expect(composed.paths.parent.values, isNot(contains(_hidden)));
      expect(composed.paths.depth.containsKey(_hidden), isFalse);
      expect(composed.paths.ring, isNot(contains(_hidden)));
      expect(composed.labelPlan.layoutRequestsByAuthor.keys,
          isNot(contains(_hidden)));
      expect(composed.labelPlan.overflowHiddenCountByAuthor.keys,
          isNot(contains(_hidden)));
      expect(
        composed.beaconNodes.map((n) => n.id).where((id) => !id.startsWith('B_auto_')),
        isEmpty,
      );

      // Drawn at its pin.
      final anchor = composed.anchorOverlay.anchors.singleWhere(
        (a) => a.target.graphNodeId == _hidden,
      );
      final layout = computeConstellationLayout(
        egoId: _ego,
        paths: composed.paths,
        keptPeerIds: composed.keptPeerIds,
        visibleRequestsByAuthor: const {},
        egoOwnRequestIds: const {},
        pinnedPersonIds: {_hidden},
        anchorByNodeId: {_hidden: anchor.position},
      );
      final egoPoint = layout.positions[_ego]!;
      final pinPoint = layout.positions[_hidden]!;
      expect(
        (pinPoint.x - egoPoint.x) / kConstellationRingUnitPixels,
        closeTo(_pinPosition.xUnits, 0.001),
      );
      expect(
        (pinPoint.y - egoPoint.y) / kConstellationRingUnitPixels,
        closeTo(_pinPosition.yUnits, 0.001),
      );
    });

    test('is not kept once unpinned from the projection', () {
      final composed = _compose(pinned: false);

      expect(composed.keptPeerIds, isNot(contains(_hidden)));
      expect(composed.eligiblePersonIds, isNot(contains(_hidden)));
      expect(composed.anchorOverlay.pinnedPeers, isEmpty);
    });

    test('is not kept when the projection has an anchor but no pinned peer', () {
      final composed = _compose(pinned: true, withPeerRecord: false);

      expect(composed.keptPeerIds, isNot(contains(_hidden)));
      expect(composed.eligiblePersonIds, isNot(contains(_hidden)));
    });

    test('is kept in the pinned overlay as not visible', () {
      final composed = _compose(pinned: true);

      expect(composed.anchorOverlay.pinnedPeers.single.visible, isFalse);
    });
  });
}
