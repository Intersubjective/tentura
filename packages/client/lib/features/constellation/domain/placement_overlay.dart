import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'entity/constellation_anchor_projection.dart';
import 'entity/placement_outbox.dart';

/// Overlays unresolved intent without changing server-confirmed coverage.
({
  ConstellationAnchorProjection projection,
  Set<ConstellationAnchorTarget> unsaved,
})
desiredAnchorProjection(
  ConstellationAnchorProjection confirmed,
  PlacementOutboxState outbox, {
  required DateTime now,
}) {
  final anchors = {
    for (final anchor in confirmed.anchors) anchor.target: anchor,
  };
  final unsaved = <ConstellationAnchorTarget>{};

  for (final entry in outbox.targets.entries) {
    final state = entry.value;
    for (final slot in [state.inFlight, state.latestPending]) {
      if (slot == null) {
        continue;
      }
      final needsCue = switch (slot.status) {
        PlacementSlotStatus.rejected => true,
        PlacementSlotStatus.commitUnknown => slot.attempts >= 3,
        PlacementSlotStatus.inFlight =>
          slot.inFlightSince != null &&
              now.difference(slot.inFlightSince!) > const Duration(seconds: 1),
        PlacementSlotStatus.queued => false,
      };
      if (needsCue) {
        unsaved.add(entry.key);
      }
    }

    final op = (state.latestPending ?? state.inFlight)?.op;
    switch (op) {
      case PlacementUpsert():
        final previous = anchors[op.target];
        anchors[op.target] = ConstellationAnchor(
          target: op.target,
          position: op.position,
          revision: previous?.revision ?? ConstellationAnchorRevision.zero,
          placedAt: previous?.placedAt ?? now,
        );
      case PlacementDelete():
        anchors.remove(op.target);
      case null:
        break;
    }
  }

  return (
    projection: ConstellationAnchorProjection(
      revision: confirmed.revision,
      anchors: List.unmodifiable(anchors.values),
      pinnedPeers: confirmed.pinnedPeers,
      pinnedRequests: confirmed.pinnedRequests,
      supportPeers: confirmed.supportPeers,
      supportEdges: confirmed.supportEdges,
      serverFilteredBeaconIds: confirmed.serverFilteredBeaconIds,
      serverFilteredBeaconCount: confirmed.serverFilteredBeaconCount,
    ),
    unsaved: Set.unmodifiable(unsaved),
  );
}
