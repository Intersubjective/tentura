import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'entity/constellation_anchor_projection.dart';
import 'entity/placement_outbox.dart';

/// How long a write may stay in flight before the user is told it is saving.
const kPlacementSavingCueDelay = Duration(seconds: 1);

/// What the user is told about a node whose placement is not yet saved.
enum PlacementCue { saving, notSaved }

PlacementCue? _cueFor(PlacementSlot slot, DateTime now) =>
    switch (slot.status) {
      PlacementSlotStatus.rejected => PlacementCue.notSaved,
      PlacementSlotStatus.commitUnknown =>
        slot.attempts >= 3 ? PlacementCue.notSaved : null,
      PlacementSlotStatus.inFlight =>
        // A discarded write is told at once: the user has already decided.
        slot.discardOnSettle ||
                (slot.inFlightSince != null &&
                    now.difference(slot.inFlightSince!) >
                        kPlacementSavingCueDelay)
            ? PlacementCue.saving
            : null,
      PlacementSlotStatus.queued => null,
    };

/// The cue per target, and how long until an in-flight write earns its cue.
({Map<ConstellationAnchorTarget, PlacementCue> cues, Duration? nextChange})
placementCues(PlacementOutboxState outbox, {required DateTime now}) {
  final cues = <ConstellationAnchorTarget, PlacementCue>{};
  Duration? nextChange;
  for (final entry in outbox.targets.entries) {
    for (final slot in [entry.value.inFlight, entry.value.latestPending]) {
      if (slot == null) continue;
      final cue = _cueFor(slot, now);
      if (cue == null) {
        final since = slot.inFlightSince;
        if (slot.status == PlacementSlotStatus.inFlight && since != null) {
          final wait = since.add(kPlacementSavingCueDelay).difference(now);
          if (nextChange == null || wait < nextChange) nextChange = wait;
        }
      } else if (cues[entry.key] != PlacementCue.notSaved) {
        cues[entry.key] = cue;
      }
    }
  }
  return (cues: cues, nextChange: nextChange);
}

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
  final unpinned = <ConstellationAnchorTarget>{};

  for (final entry in outbox.targets.entries) {
    final state = entry.value;
    for (final slot in [state.inFlight, state.latestPending]) {
      if (slot == null) {
        continue;
      }
      final needsCue = _cueFor(slot, now) != null;
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
        unpinned.add(op.target);
      case null:
        break;
    }
  }

  return (
    projection: ConstellationAnchorProjection(
      revision: confirmed.revision,
      anchors: List.unmodifiable(anchors.values),
      // An unpin also drops the entity the pin carried, as the server's
      // acknowledged projection does, so the ack changes no layout input.
      pinnedPeers: [
        for (final peer in confirmed.pinnedPeers)
          if (!unpinned.contains(ConstellationAnchorTarget.person(peer.id)))
            peer,
      ],
      pinnedRequests: [
        for (final request in confirmed.pinnedRequests)
          if (!unpinned.contains(ConstellationAnchorTarget.beacon(request.id)))
            request,
      ],
      supportPeers: confirmed.supportPeers,
      supportEdges: confirmed.supportEdges,
      serverFilteredBeaconIds: confirmed.serverFilteredBeaconIds,
      serverFilteredBeaconCount: confirmed.serverFilteredBeaconCount,
    ),
    unsaved: Set.unmodifiable(unsaved),
  );
}
